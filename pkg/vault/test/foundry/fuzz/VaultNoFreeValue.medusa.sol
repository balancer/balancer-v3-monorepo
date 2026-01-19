// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import {
    LiquidityManagement,
    PoolRoleAccounts,
    Rounding
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolFactoryMock } from "../../../contracts/test/PoolFactoryMock.sol";

import "../utils/BaseMedusaTest.sol";

/**
 * @notice Medusa suite: no-free-value properties for the Vault.
 * @dev This suite focuses on:
 *  - Conservation of ERC20 token supply (no unintended mint/burn / lost tokens).
 *  - Invariant monotonicity under swaps + donations (actions that should not reduce invariant).
 *
 * We intentionally do NOT include liquidity removals here, because removing liquidity legitimately decreases the
 * pool invariant and would make the invariant monotonicity property meaningless.
 */
contract VaultNoFreeValueMedusaTest is BaseMedusaTest {
    using FixedPoint for uint256;

    uint256 private constant _MIN_AMOUNT = 1e6;
    uint256 private constant _MAX_IN_RATIO = 0.3e18;

    uint256 private daiTotalSupply0;
    uint256 private usdcTotalSupply0;
    uint256 private wethTotalSupply0;
    uint256 private bptTotalSupply0;

    uint256 private initInvariantDown;
    uint256 private lastInvariantDown;
    bool private invariantEverDecreased;

    uint256 private lastBptRate;
    bool private bptRateEverDecreased;

    constructor() BaseMedusaTest() {
        daiTotalSupply0 = dai.totalSupply();
        usdcTotalSupply0 = usdc.totalSupply();
        wethTotalSupply0 = weth.totalSupply();
        bptTotalSupply0 = IERC20(address(pool)).totalSupply();

        initInvariantDown = _computeInvariant(Rounding.ROUND_DOWN);
        lastInvariantDown = initInvariantDown;
        lastBptRate = vault.getBptRate(address(pool));

        // Worst-case for invariant monotonicity: no LP fees to mask rounding/value leaks.
        // Circumvent minimum swap fee checks in the mock for testing purposes.
        vault.manualUnsafeSetStaticSwapFeePercentage(address(pool), 0);
    }

    function optimize_invariantDecrease() public view returns (int256) {
        // Maximize invariant drop (should remain <= 0 in a correct system since invariant shouldn't drop here).
        return int256(initInvariantDown) - int256(lastInvariantDown);
    }

    function optimize_bptRateDecrease() public view returns (int256) {
        // Maximize BPT rate drop (should remain <= 0 here).
        return int256(lastBptRate) - int256(vault.getBptRate(address(pool)));
    }

    /***************************************************************************
     *                            Actions (fuzzed)
     ***************************************************************************/

    function computeSwapExactIn(uint256 tokenIndexIn, uint256 tokenIndexOut, uint256 exactAmountIn) public {
        (tokenIndexIn, tokenIndexOut) = _boundTokenIndexes(tokenIndexIn, tokenIndexOut);
        exactAmountIn = _boundSwapAmount(exactAmountIn, tokenIndexIn);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        medusa.prank(alice);
        router.swapSingleTokenExactIn(
            address(pool),
            tokens[tokenIndexIn],
            tokens[tokenIndexOut],
            exactAmountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        _updateMonotonicityFlags();
    }

    function computeSwapExactOut(uint256 tokenIndexIn, uint256 tokenIndexOut, uint256 exactAmountOut) public {
        (tokenIndexIn, tokenIndexOut) = _boundTokenIndexes(tokenIndexIn, tokenIndexOut);
        exactAmountOut = _boundSwapAmount(exactAmountOut, tokenIndexOut);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        medusa.prank(alice);
        router.swapSingleTokenExactOut(
            address(pool),
            tokens[tokenIndexIn],
            tokens[tokenIndexOut],
            exactAmountOut,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        _updateMonotonicityFlags();
    }

    /// @dev Donate arbitrary amounts (donation enabled in pool config below). Should never mint BPT.
    function computeDonate(uint256[] memory rawAmountsIn) public {
        uint256[] memory amountsIn = _boundBalanceLength(rawAmountsIn);

        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        for (uint256 i = 0; i < amountsIn.length; i++) {
            // Keep within packed-balance headroom.
            uint256 headroom = type(uint128).max - balancesRaw[i];
            uint256 userBal = tokens[i].balanceOf(bob);
            uint256 maxDonate = headroom < userBal ? headroom : userBal;
            amountsIn[i] = bound(amountsIn[i], 0, maxDonate);
        }

        medusa.prank(bob);
        router.donate(address(pool), amountsIn, false, bytes(""));

        _updateMonotonicityFlags();
    }

    /***************************************************************************
     *                              Properties
     ***************************************************************************/

    function property_tokenConservation() public view returns (bool) {
        // If tokens are minted/burned, or end up stranded in an unexpected contract (e.g., router),
        // conservation should fail.
        return
            _tokenConserved(dai, daiTotalSupply0) &&
            _tokenConserved(usdc, usdcTotalSupply0) &&
            _tokenConserved(weth, wethTotalSupply0);
    }

    function property_invariantNonDecreasing() public view returns (bool) {
        // Stronger than ">= initial": we track whether the invariant ever dropped at any intermediate step.
        return !invariantEverDecreased && lastInvariantDown >= initInvariantDown;
    }

    function property_bptSupplyConstant() public view returns (bool) {
        // Swaps + donations must not mint/burn BPT.
        return IERC20(address(pool)).totalSupply() == bptTotalSupply0;
    }

    function property_bptRateNonDecreasing() public view returns (bool) {
        // With no liquidity removals and no BPT supply changes in this suite, the BPT rate should never go down.
        return !bptRateEverDecreased;
    }

    /***************************************************************************
     *                         Pool construction override
     ***************************************************************************/

    function createPool(IERC20[] memory tokens, uint256[] memory initialBalances) internal override returns (address newPool) {
        // Enable donation explicitly in liquidity management config.
        newPool = factoryMock.createPool("ERC20 Pool (donations enabled)", "ERC20POOL-DON");

        LiquidityManagement memory lm;
        lm.disableUnbalancedLiquidity = false;
        lm.enableAddLiquidityCustom = true;
        lm.enableRemoveLiquidityCustom = true;
        lm.enableDonation = true;

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        factoryMock.registerPool(newPool, vault.buildTokenConfig(tokens), roleAccounts, address(0), lm);

        medusa.prank(lp);
        router.initialize(address(newPool), tokens, initialBalances, 0, false, bytes(""));
    }

    /***************************************************************************
     *                               Helpers
     ***************************************************************************/

    function _computeInvariant(Rounding rounding) internal view returns (uint256) {
        (, , , uint256[] memory balancesScaled18) = vault.getPoolTokenInfo(address(pool));
        return pool.computeInvariant(balancesScaled18, rounding);
    }

    function _updateMonotonicityFlags() internal {
        // Invariant should never decrease step-to-step for swaps/donations in this harness.
        uint256 inv = _computeInvariant(Rounding.ROUND_DOWN);
        if (inv < lastInvariantDown) invariantEverDecreased = true;
        lastInvariantDown = inv;

        uint256 rate = vault.getBptRate(address(pool));
        if (rate < lastBptRate) bptRateEverDecreased = true;
        lastBptRate = rate;
    }

    function _tokenConserved(IERC20 token, uint256 expectedTotalSupply0) internal view returns (bool) {
        uint256 ts = token.totalSupply();
        if (ts != expectedTotalSupply0) return false;
        return _sumToken(token) == ts;
    }

    function _sumToken(IERC20 t) internal view returns (uint256) {
        // Track all contracts involved in the harness to avoid "tokens stranded somewhere unexpected" false negatives.
        return
            t.balanceOf(alice) +
            t.balanceOf(bob) +
            t.balanceOf(lp) +
            t.balanceOf(address(vault)) +
            t.balanceOf(address(router)) +
            t.balanceOf(address(batchRouter)) +
            t.balanceOf(address(compositeLiquidityRouter)) +
            t.balanceOf(address(pool));
    }

    function _boundTokenIndexes(
        uint256 tokenIndexInRaw,
        uint256 tokenIndexOutRaw
    ) internal view returns (uint256 tokenIndexIn, uint256 tokenIndexOut) {
        uint256 len = vault.getPoolTokens(address(pool)).length;
        tokenIndexIn = bound(tokenIndexInRaw, 0, len - 1);
        tokenIndexOut = bound(tokenIndexOutRaw, 0, len - 1);
        if (tokenIndexIn == tokenIndexOut) tokenIndexOut = (tokenIndexOut + 1) % len;
    }

    function _boundSwapAmount(uint256 tokenAmount, uint256 tokenIndex) internal view returns (uint256 boundedAmount) {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        uint256 maxIn = balancesRaw[tokenIndex].mulDown(_MAX_IN_RATIO);
        if (maxIn < _MIN_AMOUNT) maxIn = _MIN_AMOUNT;
        boundedAmount = bound(tokenAmount, _MIN_AMOUNT, maxIn);
    }

    function _boundBalanceLength(uint256[] memory balances) internal view returns (uint256[] memory) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));
        uint256 length = tokens.length;
        assembly {
            mstore(balances, length)
        }
        return balances;
    }
}

