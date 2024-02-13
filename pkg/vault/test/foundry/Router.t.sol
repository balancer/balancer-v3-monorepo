// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiToken.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Router } from "../../contracts/Router.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";
import { VaultExtensionMock } from "../../contracts/test/VaultExtensionMock.sol";

import { VaultMockDeployer } from "./utils/VaultMockDeployer.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract RouterTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal usdcAmountIn = 1e3 * 1e6;
    uint256 internal daiAmountIn = 1e3 * 1e18;
    uint256 internal daiAmountOut = 1e2 * 1e18;
    uint256 internal ethAmountIn = 1e3 ether;
    uint256 internal initBpt = 10e18;
    uint256 internal bptAmountOut = 1e18;

    PoolMock internal wethPool;
    PoolMock internal wethPoolNoInit;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        PoolMock newPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            vault.buildTokenConfig([address(dai), address(usdc)].toMemoryArray().asIERC20()),
            true,
            365 days,
            address(0)
        );
        vm.label(address(newPool), "pool");

        wethPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 weth Pool",
            "ERC20POOL",
            vault.buildTokenConfig([address(weth), address(dai)].toMemoryArray().asIERC20()),
            true,
            365 days,
            address(0)
        );
        vm.label(address(wethPool), "wethPool");

        wethPoolNoInit = new PoolMock(
            IVault(address(vault)),
            "ERC20 weth Pool",
            "ERC20POOL",
            vault.buildTokenConfig([address(weth), address(dai)].toMemoryArray().asIERC20()),
            true,
            365 days,
            address(0)
        );
        vm.label(address(wethPoolNoInit), "wethPoolNoInit");

        return address(newPool);
    }

    function initPool() internal override {
        (IERC20[] memory tokens, , , , ) = vault.getPoolTokenInfo(address(pool));
        vm.prank(lp);
        router.initialize(address(pool), tokens, [poolInitAmount, poolInitAmount].toMemoryArray(), 0, false, "");

        vm.prank(lp);
        bool wethIsEth = true;
        router.initialize{ value: ethAmountIn }(
            address(wethPool),
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            initBpt,
            wethIsEth,
            bytes("")
        );
    }

    function testQuerySwap() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(EVMCallModeHelpers.NotStaticCall.selector));
        router.querySwapExactIn(address(pool), usdc, dai, usdcAmountIn, bytes(""));
    }

    function testDisableQueries() public {
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));

        vault.disableQuery();

        // Authorize alice
        bytes32 disableQueryRole = vault.getActionId(IVaultExtension.disableQuery.selector);

        authorizer.grantRole(disableQueryRole, alice);

        vm.prank(alice);
        vault.disableQuery();

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.QueriesDisabled.selector));

        vm.prank(address(0), address(0));
        router.querySwapExactIn(address(pool), usdc, dai, usdcAmountIn, bytes(""));
    }

    function testInitializeBelowMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20MultiToken.TotalSupplyTooLow.selector, 0, 1e6));
        router.initialize(
            address(wethPoolNoInit),
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            [uint256(0), uint256(0)].toMemoryArray(),
            uint256(0),
            false,
            bytes("")
        );
    }

    function testInitializeWETHNoBalance() public {
        require(weth.balanceOf(broke) == 0, "Precondition: WETH balance non-zero");

        bool wethIsEth = false;
        // Revert when sending ETH while wethIsEth is false (caller holds no weth).
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, broke, 0, ethAmountIn));
        vm.prank(broke);
        router.initialize(
            address(wethPoolNoInit),
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            initBpt,
            wethIsEth,
            bytes("")
        );
    }

    function testInitializeWETH() public {
        checkAddLiquidityPreConditions();

        vm.prank(alice);
        bptAmountOut = router.initialize(
            address(wethPoolNoInit),
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            initBpt,
            false,
            bytes("")
        );

        // weth was deposited, pool tokens were minted to Alice.
        assertEq(weth.balanceOf(alice), defaultBalance - ethAmountIn, "Wrong WETH balance");
        assertEq(wethPoolNoInit.balanceOf(alice), bptAmountOut, "Wrong WETH pool balance");
        assertGt(bptAmountOut, 0, "bptAmountOut is zero");
    }

    function testInitializeNativeNoBalance() public {
        checkAddLiquidityPreConditions();

        // Caller does not have enough ETH, even if they hold weth.
        vm.expectRevert(abi.encodeWithSelector(IRouter.InsufficientEth.selector));
        vm.prank(alice);
        router.initialize(
            address(wethPoolNoInit),
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            initBpt,
            true,
            bytes("")
        );
    }

    function testInitializeNative() public {
        checkAddLiquidityPreConditions();

        bool wethIsEth = true;
        vm.startPrank(alice);
        bptAmountOut = router.initialize{ value: ethAmountIn }(
            address(wethPoolNoInit),
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            initBpt,
            wethIsEth,
            bytes("")
        );

        // weth was deposited, pool tokens were minted to Alice.
        assertEq(address(alice).balance, defaultBalance - ethAmountIn, "Wrong ETH balance");
        assertEq(wethPoolNoInit.balanceOf(alice), bptAmountOut, "Wrong WETH pool balance");
        assertGt(bptAmountOut, 0, "bptAmountOut is zero");
    }

    function testInitializeNativeExcessEth() public {
        checkAddLiquidityPreConditions();

        bool wethIsEth = true;
        vm.prank(alice);
        bptAmountOut = router.initialize{ value: defaultBalance }(
            address(wethPoolNoInit),
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            initBpt,
            wethIsEth,
            bytes("")
        );

        // weth was deposited, excess ETH was returned, pool tokens were minted to Alice.
        assertEq(address(alice).balance, defaultBalance - ethAmountIn, "Wrong ETH balance");
        assertEq(wethPoolNoInit.balanceOf(alice), bptAmountOut, "Wrong WETH pool balance");
        assertGt(bptAmountOut, 0, "bptAmountOut is zero");
    }

    function testAddLiquidityWETHNoBalance() public {
        checkAddLiquidityPreConditions();

        // Revert when sending ETH while wethIsEth is false (caller holds no weth).
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, broke, 0, ethAmountIn));
        vm.prank(broke);
        router.addLiquidityCustom(
            address(wethPool),
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            bptAmountOut,
            false,
            bytes("")
        );
    }

    function testAddLiquidityWETH() public {
        checkAddLiquidityPreConditions();

        vm.prank(alice);
        snapStart("routerAddLiquidityWETH");
        router.addLiquidityCustom(
            address(wethPool),
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            bptAmountOut,
            false,
            bytes("")
        );
        snapEnd();

        // weth was deposited, pool tokens were minted to Alice.
        assertEq(defaultBalance - weth.balanceOf(alice), ethAmountIn, "Wrong ETH balance");
        assertEq(wethPool.balanceOf(alice), bptAmountOut, "Wrong WETH pool balance");
    }

    function testAddLiquidityNativeNoBalance() public {
        checkAddLiquidityPreConditions();

        // Caller does not have enough ETH, even if they hold weth.
        vm.expectRevert(abi.encodeWithSelector(IRouter.InsufficientEth.selector));
        vm.prank(alice);
        router.addLiquidityCustom(
            address(wethPool),
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            bptAmountOut,
            true,
            bytes("")
        );
    }

    function testAddLiquidityNative() public {
        checkAddLiquidityPreConditions();

        snapStart("routerAddLiquidityNative");
        vm.prank(alice);
        router.addLiquidityCustom{ value: ethAmountIn }(
            address(wethPool),
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            bptAmountOut,
            true,
            bytes("")
        );
        snapEnd();

        // weth was deposited, pool tokens were minted to Alice.
        assertEq(address(alice).balance, defaultBalance - ethAmountIn, "Wrong ETH balance");
        assertEq(wethPool.balanceOf(alice), bptAmountOut, "Wrong WETH pool balance");
    }

    function testAddLiquidityNativeExcessEth() public {
        checkAddLiquidityPreConditions();

        vm.prank(alice);
        router.addLiquidityCustom{ value: defaultBalance }(
            address(wethPool),
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            bptAmountOut,
            true,
            bytes("")
        );

        // weth was deposited, excess was returned, pool tokens were minted to Alice.
        assertEq(address(alice).balance, defaultBalance - ethAmountIn, "Wrong ETH balance");
        assertEq(wethPool.balanceOf(alice), bptAmountOut, "Wrong WETH pool balance");
    }

    function testRemoveLiquidityWETH() public {
        // Make Alice an LP and remove its liquidity position afterwards
        vm.startPrank(alice);
        bool wethIsEth = true;
        uint256 exactBptAmount = bptAmountOut;

        router.addLiquidityCustom{ value: ethAmountIn }(
            address(wethPool),
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            exactBptAmount,
            wethIsEth,
            bytes("")
        );

        checkRemoveLiquidityPreConditions();

        wethIsEth = false;
        snapStart("routerRemoveLiquidityWETH");
        router.removeLiquidityCustom(
            address(wethPool),
            exactBptAmount,
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            wethIsEth,
            ""
        );
        snapEnd();

        // Liquidity position was removed, Alice gets weth back
        assertEq(weth.balanceOf(alice), defaultBalance + ethAmountIn, "Wrong WETH balance");
        assertEq(wethPool.balanceOf(alice), 0, "WETH pool balance is > 0");
        assertEq(address(alice).balance, defaultBalance - ethAmountIn, "Wrong ETH balance");
    }

    function testRemoveLiquidityNative() public {
        // Make Alice an LP and remove its liquidity position afterwards
        vm.startPrank(alice);
        bool wethIsEth = true;
        uint256 exactBptAmount = bptAmountOut;
        router.addLiquidityCustom{ value: ethAmountIn }(
            address(wethPool),
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            exactBptAmount,
            wethIsEth,
            bytes("")
        );

        uint256 aliceNativeBalanceBefore = address(alice).balance;
        checkRemoveLiquidityPreConditions();

        snapStart("routerRemoveLiquidityNative");
        router.removeLiquidityCustom(
            address(wethPool),
            exactBptAmount,
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            wethIsEth,
            ""
        );
        snapEnd();

        // Liquidity position was removed, Alice gets ETH back
        assertEq(weth.balanceOf(alice), defaultBalance, "Wrong WETH balance");
        assertEq(wethPool.balanceOf(alice), 0, "WETH pool balance is > 0");
        assertEq(address(alice).balance, aliceNativeBalanceBefore + ethAmountIn, "Wrong ETH balance");
    }

    function testSwapExactInWETH() public {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: wrong WETH balance");

        bool wethIsEth = false;

        vm.prank(alice);
        snapStart("routerSwapExactInWETH");
        uint256 outputTokenAmount = router.swapExactIn(
            address(wethPool),
            weth,
            dai,
            ethAmountIn,
            0,
            type(uint256).max,
            wethIsEth,
            ""
        );
        snapEnd();

        assertEq(weth.balanceOf(alice), defaultBalance - ethAmountIn, "Wrong WETH balance");
        assertEq(dai.balanceOf(alice), defaultBalance + outputTokenAmount, "Wrong DAI balance");
    }

    function testSwapExactOutWETH() public {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: wrong WETH balance");
        bool wethIsEth = false;

        vm.prank(alice);
        uint256 outputTokenAmount = router.swapExactOut(
            address(wethPool),
            weth,
            dai,
            daiAmountOut,
            type(uint256).max,
            type(uint256).max,
            wethIsEth,
            ""
        );

        assertEq(weth.balanceOf(alice), defaultBalance - outputTokenAmount, "Wrong WETH balance");
        assertEq(dai.balanceOf(alice), defaultBalance + daiAmountOut, "Wrong DAI balance");
    }

    function testSwapExactInNative() public {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: wrong WETH balance");
        require(alice.balance == defaultBalance, "Precondition: wrong ETH balance");

        bool wethIsEth = true;

        vm.prank(alice);
        snapStart("routerSwapExactInNative");
        router.swapExactIn{ value: ethAmountIn }(
            address(wethPool),
            weth,
            dai,
            ethAmountIn,
            0,
            type(uint256).max,
            wethIsEth,
            ""
        );
        snapEnd();

        assertEq(weth.balanceOf(alice), defaultBalance, "Wrong WETH balance");
        assertEq(dai.balanceOf(alice), defaultBalance + ethAmountIn, "Wrong DAI balance");
        assertEq(alice.balance, defaultBalance - ethAmountIn, "Wrong ETH balance");
    }

    function testSwapExactOutNative() public {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: wrong WETH balance");
        require(alice.balance == defaultBalance, "Precondition: wrong ETH balance");

        bool wethIsEth = true;

        vm.prank(alice);
        router.swapExactOut{ value: daiAmountOut }(
            address(wethPool),
            weth,
            dai,
            daiAmountOut,
            type(uint256).max,
            type(uint256).max,
            wethIsEth,
            ""
        );

        assertEq(weth.balanceOf(alice), defaultBalance, "Wrong WETH balance");
        assertEq(dai.balanceOf(alice), defaultBalance + daiAmountOut, "Wrong DAI balance");
        assertEq(alice.balance, defaultBalance - daiAmountOut, "Wrong ETH balance");
    }

    function testSwapNativeExcessEth() public {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: wrong WETH balance");
        require(alice.balance == defaultBalance, "Precondition: wrong ETH balance");

        bool wethIsEth = true;

        vm.startPrank(alice);
        router.swapExactIn{ value: defaultBalance }(
            address(wethPool),
            weth,
            dai,
            ethAmountIn,
            0,
            type(uint256).max,
            wethIsEth,
            ""
        );

        // Only ethAmountIn is sent to the router
        assertEq(weth.balanceOf(alice), defaultBalance, "Wrong WETH balance");
        assertEq(dai.balanceOf(alice), defaultBalance + ethAmountIn, "Wrong DAI balance");
        assertEq(alice.balance, defaultBalance - ethAmountIn, "Wrong ETH balance");
    }

    function testGetSingleInputArray() public {
        (uint256[] memory amountsGiven, uint256 tokenIndex) = router.getSingleInputArrayAndTokenIndex(
            address(pool),
            dai,
            1234
        );
        assertEq(amountsGiven.length, 2);
        assertEq(amountsGiven[0], 1234);
        assertEq(amountsGiven[1], 0);
        assertEq(tokenIndex, 0);

        (amountsGiven, tokenIndex) = router.getSingleInputArrayAndTokenIndex(address(pool), usdc, 4321);
        assertEq(amountsGiven.length, 2);
        assertEq(amountsGiven[0], 0);
        assertEq(amountsGiven[1], 4321);
        assertEq(tokenIndex, 1);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.TokenNotRegistered.selector));
        router.getSingleInputArrayAndTokenIndex(address(pool), weth, daiAmountIn);
    }

    function checkRemoveLiquidityPreConditions() internal view {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: Wrong WETH balance");
        require(wethPool.balanceOf(alice) == bptAmountOut, "Precondition: Wrong weth pool balance");
    }

    function checkAddLiquidityPreConditions() internal view {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: Wrong WETH balance");
        require(alice.balance == defaultBalance, "Precondition: Wrong ETH balance");
        require(wethPool.balanceOf(alice) == 0, "Precondition: Wrong weth pool balance");
    }
}
