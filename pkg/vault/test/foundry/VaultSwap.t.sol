// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultSwapTest is BaseVaultTest {
    using ArrayHelpers for *;

    PoolMock internal noInitPool;
    uint256 internal swapFee = defaultAmount / 100; // 1%
    uint256 internal protocolSwapFee = swapFee / 2; // 50%

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        noInitPool = PoolMock(createPool());
    }

    /// Swap

    function testCannotSwapWhenPaused() public {
        vault.manualPausePool(address(pool));

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, address(pool)));

        vm.prank(bob);
        router.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount,
            type(uint256).max,
            false,
            bytes("")
        );
    }

    function testSwapNotInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotInitialized.selector, address(noInitPool)));
        router.swapSingleTokenExactIn(
            address(noInitPool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount,
            type(uint256).max,
            false,
            bytes("")
        );
    }

    function testSwapLimitGivenIn() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, defaultAmount - 1, defaultAmount));
        router.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            defaultAmount - 1,
            defaultAmount,
            type(uint256).max,
            false,
            bytes("")
        );
    }

    function testSwapLimitExactOut() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, defaultAmount, defaultAmount - 1));
        router.swapSingleTokenExactOut(
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount - 1,
            type(uint256).max,
            false,
            bytes("")
        );
    }

    function testSwapSingleTokenExactIn() public {
        assertSwap(swapSingleTokenExactIn);
    }

    function swapSingleTokenExactIn() public returns (uint256 fee, uint256 protocolFee) {
        vm.prank(alice);
        snapStart("vaultSwapSingleTokenExactIn");
        router.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount,
            type(uint256).max,
            false,
            bytes("")
        );
        snapEnd();
        return (0, 0);
    }

    function testSwapSingleTokenExactOut() public {
        assertSwap(swapSingleTokenExactOut);
    }

    function swapSingleTokenExactOut() public returns (uint256 fee, uint256 protocolFee) {
        vm.prank(alice);
        snapStart("vaultSwapSingleTokenExactOut");
        router.swapSingleTokenExactOut(
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount,
            type(uint256).max,
            false,
            bytes("")
        );
        snapEnd();
        return (0, 0);
    }

    function testSwapSingleTokenExactInWithFee() public {
        assertSwap(swapSingleTokenExactInWithFee);
    }

    function swapSingleTokenExactInWithFee() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage(swapFeePercentage);

        vm.prank(alice);
        snapStart("vaultSwapSingleTokenExactInWithFee");
        router.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount - swapFee,
            type(uint256).max,
            false,
            bytes("")
        );
        snapEnd();

        return (swapFee, 0);
    }

    function testSwapSingleTokenExactInWithProtocolFee() public {
        assertSwap(swapSingleTokenExactInWithProtocolFee);
    }

    function testSwapSingleTokenExactInWithFeeInRecoveryMode() public {
        // Put pool in recovery mode
        vault.manualEnableRecoveryMode(pool);

        assertSwap(swapSingleTokenExactInWithFeeInRecoveryMode);
    }

    function swapSingleTokenExactInWithFeeInRecoveryMode() public returns (uint256 fee, uint256 protocolFee) {
        // Call regular function (which sets the protocol swap fee), but return a fee of 0 to the validation function.
        protocolFee = 0;
        (fee, ) = swapSingleTokenExactInWithProtocolFee();
    }

    function swapSingleTokenExactInWithProtocolFee() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage(swapFeePercentage);
        setProtocolSwapFeePercentage(protocolSwapFeePercentage);

        vm.prank(alice);
        snapStart("vaultSwapSingleTokenExactInWithProtocolFee");
        router.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount - swapFee,
            type(uint256).max,
            false,
            bytes("")
        );
        snapEnd();

        return (swapFee, protocolSwapFee);
    }

    function testSwapSingleTokenExactOutWithFee() public {
        assertSwap(swapSingleTokenExactOutWithFee);
    }

    function swapSingleTokenExactOutWithFee() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage(swapFeePercentage);

        vm.prank(alice);
        router.swapSingleTokenExactOut(
            address(pool),
            usdc,
            dai,
            defaultAmount - swapFee,
            defaultAmount,
            type(uint256).max,
            false,
            bytes("")
        );

        return (swapFee, 0);
    }

    function testSwapSingleTokenExactOutWithProtocolFee() public {
        assertSwap(swapSingleTokenExactOutWithProtocolFee);
    }

    function testSwapSingleTokenExactOutWithFeeInRecoveryMode() public {
        // Put pool in recovery mode
        vault.manualEnableRecoveryMode(pool);

        assertSwap(swapSingleTokenExactOutWithFeeInRecoveryMode);
    }

    function swapSingleTokenExactOutWithFeeInRecoveryMode() public returns (uint256 fee, uint256 protocolFee) {
        // Call regular function (which sets the protocol swap fee), but return a fee of 0 to the validation function.
        protocolFee = 0;
        (fee, ) = swapSingleTokenExactOutWithProtocolFee();
    }

    function swapSingleTokenExactOutWithProtocolFee() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage(swapFeePercentage);
        setProtocolSwapFeePercentage(protocolSwapFeePercentage);

        vm.prank(alice);
        router.swapSingleTokenExactOut(
            address(pool),
            usdc,
            dai,
            defaultAmount - swapFee,
            defaultAmount,
            type(uint256).max,
            false,
            bytes("")
        );

        return (swapFee, protocolSwapFee);
    }

    function testProtocolSwapFeeAccumulation() public {
        assertSwap(protocolSwapFeeAccumulation);
    }

    function protocolSwapFeeAccumulation() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage(swapFeePercentage);
        setProtocolSwapFeePercentage(protocolSwapFeePercentage);

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            defaultAmount / 2,
            defaultAmount / 2 - swapFee / 2,
            type(uint256).max,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            defaultAmount / 2,
            defaultAmount / 2 - swapFee / 2,
            type(uint256).max,
            false,
            bytes("")
        );

        return (swapFee, protocolSwapFee);
    }

    function testCollectProtocolFees() public {
        usdc.mint(bob, defaultAmount);

        setSwapFeePercentage(swapFeePercentage);
        setProtocolSwapFeePercentage(protocolSwapFeePercentage);

        vm.prank(bob);
        router.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount - swapFee,
            type(uint256).max,
            false,
            bytes("")
        );

        authorizer.grantRole(vault.getActionId(IVaultAdmin.collectProtocolFees.selector), admin);
        vm.prank(admin);
        vault.collectProtocolFees([address(dai)].toMemoryArray().asIERC20());

        // protocol fees are zero
        assertEq(0, vault.getProtocolFees(address(dai)), "Protocol fees are not zero");

        // alice received protocol fees
        assertEq(dai.balanceOf(admin) - defaultBalance, (protocolSwapFee), "Protocol fees not collected");
    }

    function reentrancyHook() public {
        // do second swap
        SwapParams memory params = SwapParams({
            kind: SwapKind.EXACT_IN,
            pool: address(pool),
            tokenIn: dai,
            tokenOut: usdc,
            amountGivenRaw: defaultAmount,
            limitRaw: 0,
            userData: bytes("")
        });
        vault.swap(params);
    }

    function startSwap() public {
        SwapParams memory params = SwapParams({
            kind: SwapKind.EXACT_IN,
            pool: address(pool),
            tokenIn: usdc,
            tokenOut: dai,
            amountGivenRaw: defaultAmount,
            limitRaw: 0,
            userData: bytes("")
        });
        vault.swap(params);
    }

    function testReentrancySwap() public {
        // Enable before swap
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.hooks.shouldCallBeforeSwap = true;
        vault.setConfig(address(pool), config);

        // Enable reentrancy hook
        PoolMock(pool).setReentrancyHookActive(true);
        PoolMock(pool).setReentrancyHook(this.reentrancyHook);

        uint256 usdcBeforeSwap = usdc.balanceOf(address(this));
        uint256 daiBeforeSwap = dai.balanceOf(address(this));

        (, , uint[] memory balancesRawBefore, , ) = vault.getPoolTokenInfo(address(pool));

        vault.lock(abi.encode(this.startSwap.selector));

        (, , uint[] memory balancesRawAfter, , ) = vault.getPoolTokenInfo(address(pool));

        // Pool balances should not change
        for (uint i = 0; i < balancesRawAfter.length; i++) {
            assertEq(balancesRawBefore[i], balancesRawAfter[i], "Balance does not match");
        }
        // No tokens being spent.
        assertEq(usdcBeforeSwap, usdc.balanceOf(address(this)), "USDC balance changed");
        assertEq(daiBeforeSwap, dai.balanceOf(address(this)), "DAI balance changed");
    }

    /// Utils

    function assertSwap(function() returns (uint256, uint256) testFunc) internal {
        uint256 usdcBeforeSwap = usdc.balanceOf(alice);
        uint256 daiBeforeSwap = dai.balanceOf(alice);

        (uint256 fee, uint256 protocolFee) = testFunc();

        // assets are transferred to/from user
        assertEq(usdc.balanceOf(alice), usdcBeforeSwap - defaultAmount, "Swap: User's USDC balance is wrong");
        assertEq(dai.balanceOf(alice), daiBeforeSwap + defaultAmount - fee, "Swap: User's DAI balance is wrong");

        // Tokens are adjusted in the pool
        (, , uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], fee - protocolFee, "Swap: Pool's [0] balance is wrong");
        assertEq(balances[1], 2 * defaultAmount, "Swap: Pool's [1] balance is wrong");

        // protocol fees are accrued
        assertEq(protocolFee, vault.getProtocolFees(address(dai)), "Swap: Protocol's fee amount is wrong");

        // vault are adjusted balances
        assertEq(dai.balanceOf(address(vault)), fee, "Swap: Vault's DAI balance is wrong");
        assertEq(usdc.balanceOf(address(vault)), 2 * defaultAmount, "Swap: Vault's USDC balance is wrong");

        // Ensure raw and last live balances are in sync after the operation
        uint256[] memory currentLiveBalances = vault.getCurrentLiveBalances(pool);
        uint256[] memory lastLiveBalances = vault.getLastLiveBalances(pool);

        assertEq(currentLiveBalances.length, lastLiveBalances.length);

        for (uint256 i = 0; i < currentLiveBalances.length; i++) {
            assertEq(currentLiveBalances[i], lastLiveBalances[i]);
        }
    }
}
