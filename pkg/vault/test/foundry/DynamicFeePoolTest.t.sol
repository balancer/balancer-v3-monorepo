// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { PoolHooksMock } from "../../contracts/test/PoolHooksMock.sol";
import { PoolConfigBits, PoolConfigLib } from "../../contracts/lib/PoolConfigLib.sol";
import { RouterCommon } from "../../contracts/RouterCommon.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract DynamicFeePoolTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    address internal noFeeReferencePool;
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        defaultBalance = 1e10 * 1e18;
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");
    }

    function createPool() internal virtual override returns (address) {
        address[] memory tokens = [address(dai), address(usdc)].toMemoryArray();

        noFeeReferencePool = _createPool(tokens, "noFeeReferencePool");

        return _createPool(tokens, "swapPool");
    }

    function _createPool(address[] memory tokens, string memory label) internal virtual override returns (address) {
        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");
        vm.label(address(newPool), label);
        PoolRoleAccounts memory roleAccounts;

        IHooks.HookFlags memory hookFlags;
        hookFlags.shouldCallComputeDynamicSwapFee = true;
        PoolHooksMock(poolHooksContract).setHookFlags(hookFlags);

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.enableAddLiquidityCustom = true;
        liquidityManagement.enableRemoveLiquidityCustom = true;

        factoryMock.registerPool(
            address(newPool),
            vault.buildTokenConfig(tokens.asIERC20()),
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );

        return address(newPool);
    }

    function initPool() internal override {
        poolInitAmount = 1e9 * 1e18;

        vm.startPrank(lp);
        _initPool(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(noFeeReferencePool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    function testSwapCallsComputeFee() public {
        IBasePool.PoolSwapParams memory poolSwapParams = IBasePool.PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: defaultAmount,
            balancesScaled18: [poolInitAmount, poolInitAmount].toMemoryArray(),
            indexIn: daiIdx,
            indexOut: usdcIdx,
            router: address(router),
            userData: bytes("")
        });

        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(PoolHooksMock.onComputeDynamicSwapFee.selector, poolSwapParams, 0),
            1 // callCount
        );

        vm.expectCall(
            pool,
            abi.encodeWithSelector(PoolMock.onSwap.selector, poolSwapParams),
            1 // callCount
        );

        vm.prank(alice);
        // Perform a swap in the pool
        router.swapSingleTokenExactIn(pool, dai, usdc, defaultAmount, 0, MAX_UINT256, false, bytes(""));
    }

    function testSwapCallsComputeFeeWithSender() public {
        IBasePool.PoolSwapParams memory poolSwapParams = IBasePool.PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: defaultAmount,
            balancesScaled18: [poolInitAmount, poolInitAmount].toMemoryArray(),
            indexIn: daiIdx,
            indexOut: usdcIdx,
            router: address(router),
            userData: bytes("")
        });

        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(PoolHooksMock.onComputeDynamicSwapFee.selector, poolSwapParams, 0),
            1 // callCount
        );

        vm.expectCall(
            pool,
            abi.encodeWithSelector(PoolMock.onSwap.selector, poolSwapParams),
            1 // callCount
        );

        // Set a 100% fee, and bob as 0 swap fee sender.
        PoolHooksMock(poolHooksContract).setDynamicSwapFeePercentage(FixedPoint.ONE);
        PoolHooksMock(poolHooksContract).setSpecialSender(bob);

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        router.swapSingleTokenExactIn(pool, dai, usdc, defaultAmount, 0, MAX_UINT256, false, bytes(""));

        uint256 aliceBalanceAfter = usdc.balanceOf(alice);
        // 100% fee; should get nothing
        assertEq(aliceBalanceAfter - aliceBalanceBefore, 0);

        // Now set Alice as the special 0-fee sender
        PoolHooksMock(poolHooksContract).setSpecialSender(alice);
        aliceBalanceBefore = aliceBalanceAfter;

        vm.prank(alice);
        router.swapSingleTokenExactIn(pool, dai, usdc, defaultAmount, 0, MAX_UINT256, false, bytes(""));

        aliceBalanceAfter = usdc.balanceOf(alice);
        // No fee; should get full swap amount
        assertEq(aliceBalanceAfter - aliceBalanceBefore, defaultAmount);
    }

    function testExternalComputeFee() public {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setStaticSwapFeePercentage(pool, 10e16);
        uint256[] memory balances;

        vm.expectCall(
            address(poolHooksContract),
            abi.encodeWithSelector(
                IHooks.onComputeDynamicSwapFee.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: 0,
                    balancesScaled18: balances,
                    indexIn: 0,
                    indexOut: 0,
                    router: address(0),
                    userData: bytes("")
                }),
                10e16
            ),
            1 // callCount
        );

        IBasePool.PoolSwapParams memory swapParams;
        uint256 dynamicSwapFeePercentage = 0.01e18;

        PoolHooksMock(poolHooksContract).setDynamicSwapFeePercentage(dynamicSwapFeePercentage);

        (bool success, uint256 actualDynamicSwapFee) = vault.computeDynamicSwapFee(pool, swapParams);

        assertTrue(success, "computeDynamicSwapFee returned false");
        assertEq(actualDynamicSwapFee, dynamicSwapFeePercentage, "Wrong dynamicSwapFeePercentage");
    }

    function testSwapChargesFees__Fuzz(uint256 dynamicSwapFeePercentage) public {
        dynamicSwapFeePercentage = bound(dynamicSwapFeePercentage, 0, 1e18);
        PoolHooksMock(poolHooksContract).setDynamicSwapFeePercentage(dynamicSwapFeePercentage);

        vm.prank(alice);
        uint256 swapAmountOut = router.swapSingleTokenExactIn(
            pool,
            dai,
            usdc,
            defaultAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        PoolHooksMock(poolHooksContract).setDynamicSwapFeePercentage(0);

        vm.prank(bob);
        uint256 liquidityAmountOut = router.swapSingleTokenExactIn(
            address(noFeeReferencePool),
            dai,
            usdc,
            defaultAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assertEq(
            swapAmountOut,
            liquidityAmountOut.mulDown(dynamicSwapFeePercentage.complement()),
            "Swap and liquidity amounts are not correct"
        );
    }
}
