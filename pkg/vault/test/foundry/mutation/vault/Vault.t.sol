// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

import { BaseVaultTest } from "../../utils/BaseVaultTest.sol";

contract VaultMutationTest is BaseVaultTest {
    using ArrayHelpers for *;

    struct TestAddLiquidityParams {
        AddLiquidityParams addLiquidityParams;
        uint256[] expectedAmountsInScaled18;
        uint256[] maxAmountsInScaled18;
        uint256[] expectSwapFeeAmountsScaled18;
        uint256 expectedBPTAmountOut;
    }

    struct TestRemoveLiquidityParams {
        RemoveLiquidityParams removeLiquidityParams;
        uint256[] expectedAmountsOutScaled18;
        uint256[] minAmountsOutScaled18;
        uint256[] expectSwapFeeAmountsScaled18;
        uint256 expectedBPTAmountIn;
    }

    uint256 immutable defaultAmountGivenRaw = 1e18;

    IERC20[] swapTokens;
    uint256[] initialBalances = [uint256(10e18), 10e18];
    uint256[] decimalScalingFactors = [uint256(1e18), 1e18];
    uint256[] tokenRates = [uint256(1e18), 2e18];
    uint256 initTotalSupply = 1000e18;

    address internal constant ZERO_ADDRESS = address(0x00);

    uint256[] internal amountsIn = [poolInitAmount, poolInitAmount].toMemoryArray();

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        swapTokens = [dai, usdc];

        vault.mintERC20(pool, address(this), initTotalSupply);
    }

    function testSettleWithLockedVault() public {
        vm.expectRevert(IVaultErrors.VaultIsNotUnlocked.selector);
        vault.settle(dai, 0);
    }

    function testSettleReentrancy() public {
        vault.forceUnlock();
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vault.manualSettleReentrancy(dai);
    }

    function testSendToWithLockedVault() public {
        vm.expectRevert(IVaultErrors.VaultIsNotUnlocked.selector);
        vault.sendTo(dai, address(0), 1);
    }

    function testSendToReentrancy() public {
        vault.forceUnlock();
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vault.manualSendToReentrancy(dai, address(0), 0);
    }

    function testSwapWithLockedVault() public {
        VaultSwapParams memory params = VaultSwapParams(SwapKind.EXACT_IN, address(pool), dai, usdc, 1, 0, bytes(""));

        vm.expectRevert(IVaultErrors.VaultIsNotUnlocked.selector);
        vault.swap(params);
    }

    function testAddLiquidityWithLockedVault() public {
        AddLiquidityParams memory params = AddLiquidityParams(
            address(pool),
            address(0),
            amountsIn,
            0,
            AddLiquidityKind.PROPORTIONAL,
            bytes("")
        );

        vm.expectRevert(IVaultErrors.VaultIsNotUnlocked.selector);
        vault.addLiquidity(params);
    }

    function testRemoveLiquidityWithLockedVault() public {
        RemoveLiquidityParams memory params = RemoveLiquidityParams(
            address(pool),
            address(0),
            0,
            amountsIn,
            RemoveLiquidityKind.PROPORTIONAL,
            bytes("")
        );

        vm.expectRevert(IVaultErrors.VaultIsNotUnlocked.selector);
        vault.removeLiquidity(params);
    }

    function testSwapReentrancy() public {
        VaultSwapParams memory params;
        SwapState memory state;
        PoolData memory poolData;

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vault.manualReentrancySwap(params, state, poolData);
    }

    function testAddLiquidityReentrancy() public {
        PoolData memory poolData;
        AddLiquidityParams memory addLiquidityParams;
        uint256[] memory maxAmountsInScaled18;

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vault.manualReentrancyAddLiquidity(poolData, addLiquidityParams, maxAmountsInScaled18);
    }

    function testRemoveLiquidityReentrancy() public {
        PoolData memory poolData;

        RemoveLiquidityParams memory removeLiquidityParams;
        uint256[] memory minAmountsOutScaled18;

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vault.manualReentrancyRemoveLiquidity(poolData, removeLiquidityParams, minAmountsOutScaled18);
    }

    function testErc4626BufferWrapOrUnwrapWhenNotUnlocked() public {
        vm.expectRevert(IVaultErrors.VaultIsNotUnlocked.selector);
        BufferWrapOrUnwrapParams memory params;
        vault.erc4626BufferWrapOrUnwrap(params);
    }

    function testErc4626BufferWrapOrUnwrapWhenNotInitialized() public {
        IERC4626 wrappedToken = IERC4626(address(123));
        vault.forceUnlock();

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferNotInitialized.selector, wrappedToken));
        BufferWrapOrUnwrapParams memory params;
        params.wrappedToken = wrappedToken;
        vault.erc4626BufferWrapOrUnwrap(params);
    }

    function testErc4626BufferWrapOrUnwrapWhenBuffersArePaused() public {
        vault.forceUnlock();
        authorizer.grantRole(vault.getActionId(IVaultAdmin.pauseVaultBuffers.selector), admin);
        vm.prank(admin);
        vault.pauseVaultBuffers();

        vm.expectRevert(IVaultErrors.VaultBuffersArePaused.selector);
        BufferWrapOrUnwrapParams memory params;
        vault.erc4626BufferWrapOrUnwrap(params);
    }

    function testErc4626BufferWrapOrUnwrapReentrancy() public {
        IERC4626 wrappedToken = IERC4626(address(123));
        address underlyingToken = address(345); // Anything non-zero
        vault.forceUnlock();
        vault.manualSetBufferAsset(wrappedToken, underlyingToken);

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        BufferWrapOrUnwrapParams memory params;
        params.wrappedToken = wrappedToken;
        vault.manualErc4626BufferWrapOrUnwrapReentrancy(params);
    }
}
