// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseMedusaTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseMedusaTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { WeightedPoolFactory } from "../../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../../contracts/WeightedPool.sol";

/**
 * @notice Donation sequencing fuzz for WeightedPool swaps.
 */
contract SwapWeightedDonationMedusaTest is BaseMedusaTest {
    using FixedPoint for uint256;

    // WeightedPool enforces a minimum swap fee for numerical stability; match it here.
    uint256 private constant MIN_SWAP_FEE = 0.001e16; // 0.001%

    uint256 private constant _WEIGHT1 = 33e16;
    uint256 private constant _WEIGHT2 = 33e16;

    uint256 internal constant MIN_SWAP_AMOUNT = 1e6;
    uint256 internal constant MAX_IN_RATIO = 0.3e18;

    int256 internal initInvariant;
    uint256 internal initBptSupply;
    uint256 private daiTotal;
    uint256 private usdcTotal;
    uint256 private wethTotal;

    constructor() BaseMedusaTest() {
        // Rounding-robust baseline:
        // - store the initial invariant rounded DOWN
        // - later compare the live invariant rounded UP
        // This avoids false failures from pow rounding wobble on tiny trades.
        initInvariant = computeInvariantDown();
        initBptSupply = IERC20(address(pool)).totalSupply();
        // These harness tokens are only minted to alice/bob/lp in BaseMedusaTest; no other address should ever
        // end up holding them besides the Vault (which custody-holds pool balances).
        daiTotal = dai.totalSupply();
        usdcTotal = usdc.totalSupply();
        wethTotal = weth.totalSupply();
    }

    function optimize_currentInvariant() public view returns (int256) {
        return -int256(computeInvariantUp());
    }

    function property_currentInvariant() public view returns (bool) {
        int256 currentInvariant = computeInvariantUp();
        return currentInvariant >= initInvariant;
    }

    function property_bpt_supply_constant() public view returns (bool) {
        return IERC20(address(pool)).totalSupply() == initBptSupply;
    }

    /// @dev Security: swaps + donations must not create/destroy tokens or leak them to unknown addresses.
    function property_token_conservation() public view returns (bool) {
        return _sum(dai) == daiTotal && _sum(usdc) == usdcTotal && _sum(weth) == wethTotal;
    }

    function computeSwapExactIn(uint256 tokenIndexIn, uint256 tokenIndexOut, uint256 exactAmountIn) public {
        (tokenIndexIn, tokenIndexOut) = boundTokenIndexes(tokenIndexIn, tokenIndexOut);
        exactAmountIn = boundSwapAmount(exactAmountIn, tokenIndexIn);

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
    }

    function computeSwapExactOut(uint256 tokenIndexIn, uint256 tokenIndexOut, uint256 exactAmountOut) public {
        (tokenIndexIn, tokenIndexOut) = boundTokenIndexes(tokenIndexIn, tokenIndexOut);
        exactAmountOut = boundSwapAmount(exactAmountOut, tokenIndexOut);

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
    }

    function createPool(IERC20[] memory tokens, uint256[] memory initialBalances) internal override returns (address) {
        uint256[] memory weights = new uint256[](3);
        weights[0] = _WEIGHT1;
        weights[1] = _WEIGHT2;
        weights[2] = 100e16 - (weights[0] + weights[1]);

        WeightedPoolFactory factory = new WeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            "Pool v1"
        );
        PoolRoleAccounts memory roleAccounts;

        WeightedPool newPool = WeightedPool(
            factory.create(
                "Weighted Pool (donations enabled)",
                "WP-DON",
                vault.buildTokenConfig(tokens),
                weights,
                roleAccounts,
                MIN_SWAP_FEE,
                address(0),
                true, // Enable donations
                false,
                bytes32(poolCreationNonce++)
            )
        );

        medusa.prank(lp);
        router.initialize(address(newPool), tokens, initialBalances, 0, false, bytes(""));

        return address(newPool);
    }

    /**
     * @notice Donate arbitrary amounts into the pool, to be interleaved with swaps in fuzz sequences.
     */
    function computeDonate(uint256[] memory rawAmountsIn) public {
        uint256[] memory amountsIn = _boundBalanceLength(rawAmountsIn);

        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        for (uint256 i = 0; i < amountsIn.length; i++) {
            amountsIn[i] = bound(amountsIn[i], 0, type(uint128).max - balancesRaw[i]);
        }

        // Avoid wasting sequences on "donate all zeros" no-ops (still keep amounts bounded above).
        bool anyNonZero;
        for (uint256 i = 0; i < amountsIn.length; i++) {
            if (amountsIn[i] != 0) {
                anyNonZero = true;
                break;
            }
        }
        if (!anyNonZero) {
            // Donate 1 wei of token0 if there is headroom; otherwise leave as a no-op.
            if (balancesRaw[0] < type(uint128).max) {
                amountsIn[0] = 1;
            }
        }

        medusa.prank(bob);
        router.donate(address(pool), amountsIn, false, bytes(""));
    }

    function computeInvariantUp() internal view returns (int256) {
        return computeInvariant(Rounding.ROUND_UP);
    }

    function computeInvariantDown() internal view returns (int256) {
        return computeInvariant(Rounding.ROUND_DOWN);
    }

    function computeInvariant(Rounding rounding) internal view returns (int256) {
        (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(address(pool));
        return int256(pool.computeInvariant(lastBalancesLiveScaled18, rounding));
    }

    function boundTokenIndexes(
        uint256 tokenIndexInRaw,
        uint256 tokenIndexOutRaw
    ) internal view returns (uint256 tokenIndexIn, uint256 tokenIndexOut) {
        uint256 len = vault.getPoolTokens(address(pool)).length;

        tokenIndexIn = bound(tokenIndexInRaw, 0, len - 1);
        tokenIndexOut = bound(tokenIndexOutRaw, 0, len - 1);

        if (tokenIndexIn == tokenIndexOut) {
            tokenIndexOut = (tokenIndexOut + 1) % len;
        }
    }

    function boundSwapAmount(uint256 tokenAmount, uint256 tokenIndex) internal view returns (uint256 boundedAmount) {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        boundedAmount = bound(tokenAmount, MIN_SWAP_AMOUNT, balancesRaw[tokenIndex].mulDown(MAX_IN_RATIO));
    }

    function _boundBalanceLength(uint256[] memory balances) internal view returns (uint256[] memory) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));
        uint256 length = tokens.length;
        assembly {
            mstore(balances, length)
        }
        return balances;
    }

    function _sum(IERC20 t) internal view returns (uint256) {
        return t.balanceOf(alice) + t.balanceOf(bob) + t.balanceOf(lp) + t.balanceOf(address(vault));
    }
}
