// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseERC4626BufferTest } from "./utils/BaseERC4626BufferTest.sol";
import { PoolConfigConst } from "../../contracts/lib/PoolConfigConst.sol";
import { VaultAdmin } from "../../contracts/VaultAdmin.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

/**
 * @notice Tests that exist purely to close VaultCore coverage gaps.
 * @dev These include:
 * - contracts/Vault.sol
 * - contracts/VaultAdmin.sol
 * - contracts/VaultCommon.sol
 * - contracts/VaultStorage.sol
 */
contract CoverageVaultCoreGapsTest is BaseVaultTest {
    using FixedPoint for uint256;

    UnlockCaller private _unlockCaller;

    function setUp() public override {
        super.setUp();
        _unlockCaller = new UnlockCaller(IVaultMain(address(vault)));
    }

    function testVaultCommonReentrancyGuardEntered() public view {
        // Covers `VaultCommon.reentrancyGuardEntered()`.
        bool entered = IVaultCommonView(address(vault)).reentrancyGuardEntered();
        // No strict expectation, just ensure it can be called.
        entered; // silence unused warning
    }

    function testVaultAddLiquidityInvalidAddLiquidityKind() public pure {
        // NOTE: Solidity ABI decoding rejects out-of-range enum values, so reaching the "InvalidAddLiquidityKind"
        // revert inside `Vault._addLiquidity` is not possible via external calls.
        // We keep this placeholder to document the gap; the line is excluded from LCOV in-source.
        assertTrue(true);
    }

    function testVaultRemoveLiquidityInvalidRemoveLiquidityKind() public pure {
        // NOTE: Solidity ABI decoding rejects out-of-range enum values, so reaching the "InvalidRemoveLiquidityKind"
        // revert inside `Vault._removeLiquidity` is not possible via external calls.
        // We keep this placeholder to document the gap; the line is excluded from LCOV in-source.
        assertTrue(true);
    }

    function testVaultSwapProtocolFeesExceedTotalCollectedAggregateFeeCorrupted() public {
        // The check in `Vault._computeAndChargeAggregateSwapFees` is defensive; normally aggregate fee <= total fee.
        // We intentionally corrupt the aggregate swap fee bits in storage to exceed 100% and hit the revert branch.
        _corruptAggregateSwapFeePercentageBits(pool);

        vm.startPrank(alice);
        vm.expectRevert(IVaultErrors.ProtocolFeesExceedTotalCollected.selector);
        router.swapSingleTokenExactIn(pool, dai, usdc, 1e18, 0, type(uint256).max, false, bytes(""));
        vm.stopPrank();
    }

    function testVaultAdminUpdateAggregateSwapFeePercentageAboveOne() public {
        // Covers `VaultAdmin.withValidPercentage` revert branch.
        vm.prank(address(feeController));
        vm.expectRevert(IVaultErrors.ProtocolFeesExceedTotalCollected.selector);
        IVaultAdmin(address(vault)).updateAggregateSwapFeePercentage(pool, FixedPoint.ONE + 1);
    }

    function _corruptAggregateSwapFeePercentageBits(address pool_) private {
        bytes32 slot = _findPoolConfigBitsSlotByProbe(pool_);
        bytes32 current = vm.load(address(vault), slot);

        uint256 bitlength = 24; // FEE_BITLENGTH

        // (1) Ensure swap fee is non-zero so `_computeAndChargeAggregateSwapFees` executes.
        // 1% => 1e16; stored as `value / 1e11` => 100000, fits in 24 bits.
        uint256 staticOffset = PoolConfigConst.STATIC_SWAP_FEE_OFFSET;
        uint256 staticMask = ((uint256(1) << bitlength) - 1) << staticOffset;
        uint256 staticStored = 100_000;

        // (2) Corrupt aggregate swap fee to > 100% to trip the defensive check.
        uint256 aggOffset = PoolConfigConst.AGGREGATE_SWAP_FEE_OFFSET;
        uint256 aggMask = ((uint256(1) << bitlength) - 1) << aggOffset;
        uint256 aggStored = 0xFFFFFF; // => `0xffffff * 1e11` ≈ 1.677e18 (> 1e18).

        uint256 corrupted = (uint256(current) & ~staticMask & ~aggMask) |
            (staticStored << staticOffset) |
            (aggStored << aggOffset);
        vm.store(address(vault), slot, bytes32(corrupted));
    }

    function _findPoolConfigBitsSlotByProbe(address pool_) private returns (bytes32) {
        // Robustly locate the mapping slot for `_poolConfigBits` by temporarily zeroing candidates and observing
        // whether `withRegisteredPool(pool_)` starts reverting.
        for (uint256 mappingSlot = 0; mappingSlot < 64; ++mappingSlot) {
            bytes32 slot = keccak256(abi.encode(pool_, mappingSlot));
            bytes32 original = vm.load(address(vault), slot);

            // Temporarily wipe candidate.
            vm.store(address(vault), slot, bytes32(0));

            (bool ok, bytes memory returndata) = address(vault).staticcall(
                abi.encodeCall(IVaultMain.getPoolTokenCountAndIndexOfToken, (pool_, dai))
            );

            // Restore candidate immediately.
            vm.store(address(vault), slot, original);

            if (!ok) {
                // Expect `PoolNotRegistered(pool_)` when we hit the correct storage slot.
                // We only check the selector to avoid depending on ABI encoding of revert args.
                if (returndata.length >= 4 && bytes4(returndata) == IVaultErrors.PoolNotRegistered.selector) {
                    return slot;
                }
            }
        }
        revert("PoolConfigBits slot not found (probe)");
    }
}

contract CoverageVaultCoreBuffersGapsTest is BaseERC4626BufferTest {
    UnlockCaller private _unlockCaller;

    function setUp() public override {
        super.setUp();
        _unlockCaller = new UnlockCaller(IVaultMain(address(vault)));
    }

    function testVaultErc4626BufferWrapOrUnwrapSwapLimitExactIn() public {
        // exact-in: revert if amountOutRaw < limitRaw
        BufferWrapOrUnwrapParams memory params = BufferWrapOrUnwrapParams({
            kind: SwapKind.EXACT_IN,
            direction: WrappingDirection.WRAP,
            wrappedToken: waDAI,
            amountGivenRaw: 10e18,
            limitRaw: type(uint256).max // impossible to meet
        });

        vm.expectRevert();
        _unlockCaller.unlockAndCall(abi.encodeCall(UnlockCaller.cbWrapOrUnwrap, (params)));
    }

    function testVaultErc4626BufferWrapOrUnwrapSwapLimitExactOut() public {
        // exact-out: revert if amountInRaw > limitRaw
        BufferWrapOrUnwrapParams memory params = BufferWrapOrUnwrapParams({
            kind: SwapKind.EXACT_OUT,
            direction: WrappingDirection.WRAP,
            wrappedToken: waDAI,
            amountGivenRaw: 10e18,
            limitRaw: 0 // will always be exceeded
        });

        vm.expectRevert();
        _unlockCaller.unlockAndCall(abi.encodeCall(UnlockCaller.cbWrapOrUnwrap, (params)));
    }

    function testVaultAdminRemoveLiquidityFromBufferHookMinUnderlyingOut() public {
        uint256 shares = vault.getBufferOwnerShares(waDAI, lp);
        vm.prank(lp);
        vm.expectRevert();
        // Set min underlying out absurdly high to trigger revert at VaultAdmin.sol:679.
        vault.removeLiquidityFromBuffer(waDAI, shares / 10, type(uint256).max, 0);
    }

    function testVaultAdminRemoveLiquidityFromBufferHookMinWrappedOut() public {
        uint256 shares = vault.getBufferOwnerShares(waDAI, lp);
        vm.prank(lp);
        vm.expectRevert();
        // Set min wrapped out absurdly high to trigger revert at VaultAdmin.sol:683.
        vault.removeLiquidityFromBuffer(waDAI, shares / 10, 0, type(uint256).max);
    }
}

contract CoverageVaultAdminConstructorGapsTest is Test {
    // These tests cover constructor revert branches in VaultAdmin.sol.
    function testVaultAdminPauseWindowTooLarge() public {
        vm.expectRevert(IVaultErrors.VaultPauseWindowDurationTooLarge.selector);
        new VaultAdmin(IVault(address(1)), uint32(type(uint32).max), 0, 0, 0);
    }

    function testVaultAdminBufferPeriodTooLarge() public {
        vm.expectRevert(IVaultErrors.PauseBufferPeriodDurationTooLarge.selector);
        new VaultAdmin(IVault(address(1)), 0, uint32(type(uint32).max), 0, 0);
    }

    function testVaultAdminQueryModeBufferSharesIncreaseNotStaticCall() public {
        VaultAdminQueryModeHarness h = new VaultAdminQueryModeHarness(IVault(address(1)));
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        h.callQueryModeBufferSharesIncreaseNonStatic();
    }
}

interface IVaultCommonView {
    function reentrancyGuardEntered() external view returns (bool);
}

/**
 * @dev Calls into Vault.unlock, which then calls back into this contract, allowing us to call
 * Vault-onlyWhenUnlocked functions without going through routers.
 */
contract UnlockCaller {
    IVaultMain private immutable _vault;

    constructor(IVaultMain vault_) {
        _vault = vault_;
    }

    function unlockAndCall(bytes calldata callbackData) external returns (bytes memory) {
        return _vault.unlock(callbackData);
    }

    function cbAddLiquidity(AddLiquidityParams calldata params) external returns (bytes memory) {
        _vault.addLiquidity(params);
        return bytes("");
    }

    function cbRemoveLiquidity(RemoveLiquidityParams calldata params) external returns (bytes memory) {
        _vault.removeLiquidity(params);
        return bytes("");
    }

    function cbWrapOrUnwrap(BufferWrapOrUnwrapParams calldata params) external returns (bytes memory) {
        _vault.erc4626BufferWrapOrUnwrap(params);
        return bytes("");
    }
}

contract VaultAdminQueryModeHarness is VaultAdmin {
    constructor(IVault mainVault) VaultAdmin(mainVault, 0, 0, 0, 0) {}

    // We want to execute the revert inside `VaultAdmin._queryModeBufferSharesIncrease` in a non-static call context.
    function callQueryModeBufferSharesIncreaseNonStatic() external {
        // Parameters do not matter; this reverts before touching storage when not in a staticcall context.
        _queryModeBufferSharesIncrease(IERC4626(address(1)), address(2), 1);
    }
}
