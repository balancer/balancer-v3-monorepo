// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

import { VaultUtils } from "./utils/VaultUtils.sol";

contract VaultSwapTest is VaultUtils {
    using ArrayHelpers for *;

    PoolMock internal noInitPool;
    uint256 internal swapFee = 1e3 * 1e16; // 1%
    uint256 internal protocolSwapFee = swapFee / 2;

    function setUp() public virtual override {
        VaultUtils.setUp();

        noInitPool = createPool();
    }

    /// Utils

    function setSwapFeePercentage() internal {
        authorizer.grantRole(vault.getActionId(IVault.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setStaticSwapFeePercentage(address(pool), 1e16); // 1%
    }

    function setProtocolSwapFeePercentage() internal {
        authorizer.grantRole(vault.getActionId(IVault.setProtocolSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setProtocolSwapFeePercentage(50e16); // %50
    }

    /// Swap

    function testCannotSwapWhenPaused() public {
        vault.manualPausePool(address(pool));

        vm.expectRevert(abi.encodeWithSelector(IVault.PoolPaused.selector, address(pool)));

        vm.prank(bob);
        router.swapExactIn(address(pool), usdc, dai, defaultAmount, defaultAmount, type(uint256).max, false, bytes(""));
    }

    function testSwapNotInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(IVault.PoolNotInitialized.selector, address(noInitPool)));
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
        vm.prank(bob);
        router.swapExactIn(address(pool), usdc, dai, defaultAmount, defaultAmount, type(uint256).max, false, bytes(""));

        // Tokens are transferred to/from Bob
        assertEq(usdc.balanceOf(bob), 0);
        assertEq(dai.balanceOf(bob), 2 * defaultAmount);

        // Tokens are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], 0);
        assertEq(balances[1], defaultAmount * 2);

        assertEq(dai.balanceOf(address(vault)), 0);
        assertEq(usdc.balanceOf(address(vault)), 2 * defaultAmount);
    }

    function testSwapGivenOut() public {
        vm.prank(bob);
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

        // asssets are transferred to/from Bob
        assertEq(usdc.balanceOf(bob), 0);
        assertEq(dai.balanceOf(bob), 2 * defaultAmount);

        // Tokens are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], 0);
        assertEq(balances[1], defaultAmount * 2);

        // vault are adjusted balances
        assertEq(dai.balanceOf(address(vault)), 0);
        assertEq(usdc.balanceOf(address(vault)), 2 * defaultAmount);
    }

    function testSwapFeeGivenIn() public {
        usdc.mint(bob, defaultAmount);

        setSwapFeePercentage();

        uint256 bobUsdcBeforeSwap = usdc.balanceOf(bob);
        uint256 bobDaiBeforeSwap = dai.balanceOf(bob);

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

        // asssets are transferred to/from Bob
        assertEq(usdc.balanceOf(bob), bobUsdcBeforeSwap - defaultAmount);
        assertEq(dai.balanceOf(bob), bobDaiBeforeSwap + defaultAmount - swapFee);

        // Tokens are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], swapFee);
        assertEq(balances[1], 2 * defaultAmount);

        // vault are adjusted balances
        assertEq(dai.balanceOf(address(vault)), swapFee);
        assertEq(usdc.balanceOf(address(vault)), 2 * defaultAmount);
    }

    function testProtocolSwapFeeGivenIn() public {
        usdc.mint(bob, defaultAmount);

        setSwapFeePercentage();
        setProtocolSwapFeePercentage();

        uint256 bobUsdcBeforeSwap = usdc.balanceOf(bob);
        uint256 bobDaiBeforeSwap = dai.balanceOf(bob);

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

        // asssets are transferred to/from Bob: usdc in, dai out
        assertEq(dai.balanceOf(bob), bobDaiBeforeSwap + defaultAmount - swapFee);
        assertEq(usdc.balanceOf(bob), bobUsdcBeforeSwap - defaultAmount);

        // Tokens are adjusted in the pool: dai out, usdc in
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], swapFee - protocolSwapFee);
        assertEq(balances[1], 2 * defaultAmount);

        // protocol fees are accrued
        assertEq(protocolSwapFee, vault.getProtocolSwapFee(address(dai)));

        // vault are adjusted balances
        assertEq(dai.balanceOf(address(vault)), swapFee);
        assertEq(usdc.balanceOf(address(vault)), 2 * defaultAmount);
    }

    function testSwapFeeGivenOut() public {
        usdc.mint(bob, defaultAmount);

        setSwapFeePercentage();

        uint256 bobUsdcBeforeSwap = usdc.balanceOf(bob);
        uint256 bobDaiBeforeSwap = dai.balanceOf(bob);

        vm.prank(bob);
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

        // asssets are transferred to/from Bob
        assertEq(usdc.balanceOf(bob), bobUsdcBeforeSwap - defaultAmount);
        assertEq(dai.balanceOf(bob), bobDaiBeforeSwap + defaultAmount - swapFee);

        // Tokens are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], swapFee);
        assertEq(balances[1], 2 * defaultAmount);

        // vault are adjusted balances
        assertEq(dai.balanceOf(address(vault)), swapFee);
        assertEq(usdc.balanceOf(address(vault)), 2 * defaultAmount);
    }

    function testProtocolSwapFeeGivenOut() public {
        usdc.mint(bob, defaultAmount);

        setSwapFeePercentage();
        setProtocolSwapFeePercentage();

        uint256 bobUsdcBeforeSwap = usdc.balanceOf(bob);
        uint256 bobDaiBeforeSwap = dai.balanceOf(bob);

        vm.prank(bob);
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

        // asssets are transferred to/from Bob
        assertEq(usdc.balanceOf(bob), bobUsdcBeforeSwap - defaultAmount);
        assertEq(dai.balanceOf(bob), bobDaiBeforeSwap + defaultAmount - swapFee);

        // Tokens are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], swapFee - protocolSwapFee);
        assertEq(balances[1], 2 * defaultAmount);

        // protocol fees are accrued
        assertEq(protocolSwapFee, vault.getProtocolSwapFee(address(dai)));

        // vault are adjusted balances
        assertEq(dai.balanceOf(address(vault)), swapFee);
        assertEq(usdc.balanceOf(address(vault)), 2 * defaultAmount);
    }

    function testProtocolSwapFeeAccumulation() public {
        usdc.mint(bob, defaultAmount);

        setSwapFeePercentage();
        setProtocolSwapFeePercentage();

        uint256 bobUsdcBeforeSwap = usdc.balanceOf(bob);
        uint256 bobDaiBeforeSwap = dai.balanceOf(bob);

        vm.prank(bob);
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

        vm.prank(bob);
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

        // asssets are transferred to/from Bob
        assertEq(usdc.balanceOf(bob), bobUsdcBeforeSwap - defaultAmount);
        assertEq(dai.balanceOf(bob), bobDaiBeforeSwap + defaultAmount - swapFee);

        // Tokens are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], swapFee - protocolSwapFee);
        assertEq(balances[1], 2 * defaultAmount);

        // protocol fees are accrued
        assertEq(protocolSwapFee, vault.getProtocolSwapFee(address(dai)));

        // vault are adjusted balances
        assertEq(dai.balanceOf(address(vault)), swapFee);
        assertEq(usdc.balanceOf(address(vault)), 2 * defaultAmount);
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

        authorizer.grantRole(vault.getActionId(IVault.collectProtocolFees.selector), admin);
        vm.prank(admin);
        vault.collectProtocolFees([address(dai)].toMemoryArray().asIERC20());

        // protocol fees are zero
        assertEq(0, vault.getProtocolSwapFee(address(dai)));

        // alice received protocol fees
        assertEq(dai.balanceOf(admin), (protocolSwapFee));
    }

    /// Utils

    function assertSwap(function() testFunc) internal {
        uint256 usdcBeforeSwap = usdc.balanceOf(alice);
        uint256 daiBeforeSwap = dai.balanceOf(alice);

        testFunc();

        // asssets are transferred to/from user
        assertEq(usdc.balanceOf(alice), usdcBeforeSwap - defaultAmount, "Swap: User's USDC balance is wrong");
        assertEq(dai.balanceOf(alice), daiBeforeSwap + defaultAmount - swapFee, "Swap: User's DAI balance is wrong");

        // Tokens are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], swapFee - protocolSwapFee, "Swap: Pool's [0] balance is wrong");
        assertEq(balances[1], 2 * defaultAmount, "Swap: Pool's [1] balance is wrong");

        // protocol fees are accrued
        assertEq(protocolSwapFee, vault.getProtocolSwapFee(address(dai)), "Swap: Protocol's fee amount is wrong");

        // vault are adjusted balances
        assertEq(dai.balanceOf(address(vault)), swapFee, "Swap: Vault's DAI balance is wrong");
        assertEq(usdc.balanceOf(address(vault)), 2 * defaultAmount, "Swap: Vault's USDC balance is wrong");
    }
}
