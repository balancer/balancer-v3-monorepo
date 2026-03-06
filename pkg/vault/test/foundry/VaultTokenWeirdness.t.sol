// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

/**
 * @notice Vault tests for "weird" ERC20 behaviors that commonly cause accounting bugs.
 * @dev The Vault should either:
 *  - handle the token safely (using actual balance deltas), or
 *  - revert cleanly without state corruption.
 */
contract VaultTokenWeirdnessTest is BaseVaultTest {
    using ArrayHelpers for *;

    struct SwapPreState {
        uint256 rate;
        uint256 invariant;
        uint256 balInRaw;
        uint256 balOutRaw;
        uint256 scaleIn;
        uint256 scaleOut;
    }

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testFeeOnTransferTokenAddLiquidityRevertsAndPoolNotInitialized() public {
        FeeOnTransferERC20 feeToken = new FeeOnTransferERC20("FOT", "FOT", 18, 100); // 1% fee
        feeToken.mint(lp, 1_000_000e18);

        // Approve Permit2+routers for feeToken (BaseVaultTest only approved its default tokens).
        _approveTokenForUser(address(feeToken), lp);

        IERC20[] memory toks = new IERC20[](2);
        toks[0] = IERC20(address(feeToken));
        toks[1] = dai;
        toks = InputHelpers.sortTokens(toks);

        address p = PoolFactoryMock(poolFactory).createPool("FOT Pool", "FOTPOOL");
        PoolFactoryMock(poolFactory).registerTestPool(p, vault.buildTokenConfig(toks), poolHooksContract, lp);

        uint256[] memory amounts = new uint256[](2);
        // Assign amounts by token address (don't rely on sorting producing a specific order).
        for (uint256 i = 0; i < toks.length; i++) {
            if (address(toks[i]) == address(feeToken)) amounts[i] = 10_000e18;
            else amounts[i] = 12_345e18;
        }

        // Fee-on-transfer means Permit2 transfers less than the Vault expects; the unlock should revert with
        // BalanceNotSettled (debt remains).
        vm.prank(lp);
        vm.expectRevert(IVaultErrors.BalanceNotSettled.selector);
        router.initialize(p, toks, amounts, 0, false, bytes(""));
    }

    function testOddDecimalsTokensSwapExactInDoesNotBreakBptRate__Fuzz(uint256 rawAmountIn) public {
        (address p, IERC20[] memory toks) = _deployOddDecimalsPool();
        _assertSwapDoesNotBreakBptRate(p, toks, rawAmountIn);
    }

    function _deployOddDecimalsPool() internal returns (address p, IERC20[] memory toks) {
        ERC20DecimalsToken usdc6 = new ERC20DecimalsToken("USDC6", "USDC6", 6);
        ERC20DecimalsToken wbtc8 = new ERC20DecimalsToken("WBTC8", "WBTC8", 8);

        usdc6.mint(lp, 1_000_000_000e6);
        wbtc8.mint(lp, 1_000_000_000e8);
        usdc6.mint(alice, 1_000_000_000e6);
        wbtc8.mint(alice, 1_000_000_000e8);

        _approveTokenForUser(address(usdc6), lp);
        _approveTokenForUser(address(wbtc8), lp);
        _approveTokenForUser(address(usdc6), alice);
        _approveTokenForUser(address(wbtc8), alice);

        toks = new IERC20[](2);
        toks[0] = IERC20(address(usdc6));
        toks[1] = IERC20(address(wbtc8));
        toks = InputHelpers.sortTokens(toks);

        p = PoolFactoryMock(poolFactory).createPool("OddDec Pool", "ODD");
        PoolFactoryMock(poolFactory).registerTestPool(p, vault.buildTokenConfig(toks), poolHooksContract, lp);

        uint256[] memory amounts = new uint256[](2);
        // Give sizeable but intentionally asymmetric initial balances in raw units (forces distinct scaling paths).
        for (uint256 i = 0; i < toks.length; i++) {
            if (address(toks[i]) == address(usdc6)) amounts[i] = 1_234_567e6;
            else amounts[i] = 9_876e8;
        }

        vm.prank(lp);
        router.initialize(p, toks, amounts, 0, false, bytes(""));
    }

    function _assertSwapDoesNotBreakBptRate(address p, IERC20[] memory toks, uint256 rawAmountIn) internal {
        // Swap small fraction of pool balance; check rate doesn't decrease beyond tiny tolerance.
        SwapPreState memory pre = _getSwapPreState(p);

        // PoolMock effectively swaps 1:1 in scaled18 terms (no pricing curve). With differing decimals, this can
        // imply a large raw `tokenOut` for a given raw `tokenIn`. Bound `amountIn` so that:
        //   amountInRaw * scaleIn <= balanceOutRaw * scaleOut
        // which guarantees `amountOutRaw <= balanceOutRaw` and avoids arithmetic underflow inside the Vault.
        uint256 maxIn = _computeMaxIn(pre);
        if (maxIn == 0) return;

        uint256 amountIn = bound(rawAmountIn, 1, maxIn);

        vm.prank(alice);
        uint256 out = router.swapSingleTokenExactIn(
            p,
            toks[0],
            toks[1],
            amountIn,
            0,
            type(uint256).max,
            false,
            bytes("")
        );
        assertGt(out, 0, "swap should produce output");

        (uint256 rateAfter, uint256 invariantAfter) = _getSwapPostState(p);

        // With rounding-down invariant/rate math, allow a tiny tolerance, but large decreases indicate a scaling bug.
        assertGe(invariantAfter + 2, pre.invariant, "invariant should not decrease beyond dust");
        assertGe(rateAfter + 2, pre.rate, "BPT rate should not decrease beyond dust");
    }

    function _getSwapPreState(address p) internal view returns (SwapPreState memory s) {
        s.rate = vault.getBptRate(p);
        (, , uint256[] memory balancesRaw, uint256[] memory balancesLiveScaled18) = vault.getPoolTokenInfo(p);
        s.invariant = IBasePool(p).computeInvariant(balancesLiveScaled18, Rounding.ROUND_DOWN);

        (uint256[] memory decimalScalingFactors, ) = vault.getPoolTokenRates(p);
        s.balInRaw = balancesRaw[0];
        s.balOutRaw = balancesRaw[1];
        s.scaleIn = decimalScalingFactors[0];
        s.scaleOut = decimalScalingFactors[1];
    }

    function _getSwapPostState(address p) internal view returns (uint256 rate, uint256 invariant) {
        rate = vault.getBptRate(p);
        (, , , uint256[] memory balancesLiveScaled18) = vault.getPoolTokenInfo(p);
        invariant = IBasePool(p).computeInvariant(balancesLiveScaled18, Rounding.ROUND_DOWN);
    }

    function _computeMaxIn(SwapPreState memory pre) internal pure returns (uint256) {
        uint256 maxInByBalanceIn = pre.balInRaw / 100; // 1% of input balance
        uint256 maxInByBalanceOut = (pre.balOutRaw * pre.scaleOut) / pre.scaleIn;
        maxInByBalanceOut = maxInByBalanceOut / 100; // 1% of the out-balance in "in-units" (conservative)
        return maxInByBalanceIn < maxInByBalanceOut ? maxInByBalanceIn : maxInByBalanceOut;
    }

    function _approveTokenForUser(address token, address user) internal {
        vm.startPrank(user);
        IERC20(token).approve(address(permit2), type(uint256).max);
        IPermit2(address(permit2)).approve(token, address(router), type(uint160).max, type(uint48).max);
        IPermit2(address(permit2)).approve(token, address(batchRouter), type(uint160).max, type(uint48).max);
        IPermit2(address(permit2)).approve(
            token,
            address(compositeLiquidityRouter),
            type(uint160).max,
            type(uint48).max
        );
        vm.stopPrank();
    }
}

/**
 * @notice ERC20 that charges a fee (burn) on transfer/transferFrom.
 * @dev This breaks the Router/Vault assumption that an exact amount was transferred, so operations should
 * safely revert.
 */
contract FeeOnTransferERC20 is ERC20 {
    uint8 private immutable _decimals;
    uint256 private immutable _feeBps;

    constructor(string memory n, string memory s, uint8 d, uint256 feeBps) ERC20(n, s) {
        _decimals = d;
        _feeBps = feeBps;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0) && _feeBps != 0) {
            uint256 fee = (amount * _feeBps) / 10_000;
            uint256 sendAmount = amount - fee;
            super._update(from, to, sendAmount);
            if (fee != 0) super._update(from, address(0), fee);
            return;
        }
        super._update(from, to, amount);
    }
}

/// @dev Simple ERC20 with configurable decimals (used for odd-decimals scaling paths).
contract ERC20DecimalsToken is ERC20 {
    uint8 private immutable _decimals;

    constructor(string memory n, string memory s, uint8 d) ERC20(n, s) {
        _decimals = d;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
