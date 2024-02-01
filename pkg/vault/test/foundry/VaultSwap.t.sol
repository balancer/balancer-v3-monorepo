// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

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

    /// Utils

    function setSwapFeePercentage() internal {
        authorizer.grantRole(vault.getActionId(IVaultExtension.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setStaticSwapFeePercentage(address(pool), 1e16); // 1%
    }

    function setProtocolSwapFeePercentage() internal {
        authorizer.grantRole(vault.getActionId(IVaultExtension.setProtocolSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setProtocolSwapFeePercentage(50e16); // %50
    }

    /// Swap

    function testCannotSwapWhenPaused() public {
        vault.manualPausePool(address(pool));

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, address(pool)));

        vm.prank(bob);
        router.swapExactIn(address(pool), usdc, dai, defaultAmount, defaultAmount, type(uint256).max, false, bytes(""));
    }

    function testSwapNotInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotInitialized.selector, address(noInitPool)));
        router.swapExactIn(
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

    function testSwapGivenIn() public {
        assertSwap(swapGivenIn);
    }

    function swapGivenIn() public returns (uint256 fee, uint256 protocolFee) {
        vm.prank(alice);
        snapStart("vaultSwapExactIn");
        router.swapExactIn(address(pool), usdc, dai, defaultAmount, defaultAmount, type(uint256).max, false, bytes(""));
        snapEnd();
        return (0, 0);
    }

    function testSwapGivenOut() public {
        assertSwap(swapGivenOut);
    }

    function swapGivenOut() public returns (uint256 fee, uint256 protocolFee) {
        vm.prank(alice);
        snapStart("vaultSwapExactIn");
        router.swapExactOut(
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

    function testSwapLimitGivenIn() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, defaultAmount - 1, defaultAmount));
        router.swapExactIn(
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

    function testSwapLimitGivenOut() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, defaultAmount, defaultAmount - 1));
        router.swapExactOut(
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

    function testSwapFeeGivenIn() public {
        assertSwap(swapFeeGivenIn);
    }

    function swapFeeGivenIn() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage();

        vm.prank(alice);
        snapStart("vaultSwapFeeGivenIn");
        router.swapExactIn(
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

    function testProtocolSwapFeeGivenIn() public {
        assertSwap(protocolSwapFeeGivenIn);
    }

    function protocolSwapFeeGivenIn() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage();
        setProtocolSwapFeePercentage();

        vm.prank(alice);
        snapStart("vaultProtocolSwapFeeGivenIn");
        router.swapExactIn(
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

    function testSwapFeeGivenOut() public {
        assertSwap(swapFeeGivenOut);
    }

    function swapFeeGivenOut() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage();

        vm.prank(alice);
        router.swapExactOut(
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

    function testProtocolSwapFeeGivenOut() public {
        assertSwap(protocolSwapFeeGivenOut);
    }

    function protocolSwapFeeGivenOut() public returns (uint256 fee, uint256 protocolFee) {
        setSwapFeePercentage();
        setProtocolSwapFeePercentage();

        vm.prank(alice);
        router.swapExactOut(
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
        setSwapFeePercentage();
        setProtocolSwapFeePercentage();

        vm.prank(alice);
        router.swapExactIn(
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
        router.swapExactIn(
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

        setSwapFeePercentage();
        setProtocolSwapFeePercentage();

        vm.prank(bob);
        router.swapExactIn(
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount - swapFee,
            type(uint256).max,
            false,
            bytes("")
        );

        authorizer.grantRole(vault.getActionId(IVaultExtension.collectProtocolFees.selector), admin);
        vm.prank(admin);
        vault.collectProtocolFees([address(dai)].toMemoryArray().asIERC20());

        // protocol fees are zero
        assertEq(0, vault.getProtocolFees(address(dai)), "Protocol fees are not zero");

        // alice received protocol fees
        assertEq(dai.balanceOf(admin) - defaultBalance, (protocolSwapFee), "Protocol fees not collected");
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
    }
}
