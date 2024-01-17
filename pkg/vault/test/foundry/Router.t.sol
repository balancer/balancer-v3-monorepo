// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { TokenNotRegistered } from "@balancer-labs/v3-interfaces/contracts/vault/VaultErrors.sol";
import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiToken.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

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

    uint256 constant USDC_AMOUNT_IN = 1e3 * 1e6;
    uint256 constant DAI_AMOUNT_IN = 1e3 * 1e18;
    uint256 constant DAI_AMOUNT_OUT = 1e2 * 1e18;
    uint256 constant ETH_AMOUNT_IN = 1e3 ether;
    uint256 constant INIT_BPT = 10e18;
    uint256 constant BPT_AMOUNT_OUT = 1e18;

    PoolMock internal wethPool;
    PoolMock internal wethPoolNoInit;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        PoolMock newPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );
        vm.label(address(newPool), "pool");

        wethPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 weth Pool",
            "ERC20POOL",
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );
        vm.label(address(wethPool), "wethPool");

        wethPoolNoInit = new PoolMock(
            IVault(address(vault)),
            "ERC20 weth Pool",
            "ERC20POOL",
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            rateProviders,
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
        router.initialize{ value: ETH_AMOUNT_IN }(
            address(wethPool),
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            INIT_BPT,
            wethIsEth,
            bytes("")
        );
    }

    function testQuerySwap() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(EVMCallModeHelpers.NotStaticCall.selector));
        router.querySwapExactIn(address(pool), usdc, dai, USDC_AMOUNT_IN, bytes(""));
    }

    function testDisableQueries() public {
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));

        vault.disableQuery();

        // Authorize alice
        bytes32 disableQueryRole = vault.getActionId(IVaultMain.disableQuery.selector);

        authorizer.grantRole(disableQueryRole, alice);

        vm.prank(alice);
        vault.disableQuery();

        vm.expectRevert(abi.encodeWithSelector(IVaultMain.QueriesDisabled.selector));

        vm.prank(address(0), address(0));
        router.querySwapExactIn(address(pool), usdc, dai, USDC_AMOUNT_IN, bytes(""));
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
        require(weth.balanceOf(broke) == 0);

        bool wethIsEth = false;
        // Revert when sending ETH while wethIsEth is false (caller holds no weth).
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, broke, 0, ETH_AMOUNT_IN)
        );
        vm.prank(broke);
        router.initialize(
            address(wethPoolNoInit),
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            INIT_BPT,
            wethIsEth,
            bytes("")
        );
    }

    function testInitializeWETH() public {
        checkPreConditions();

        vm.prank(alice);
        uint256 bptAmountOut = router.initialize(
            address(wethPoolNoInit),
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            INIT_BPT,
            false,
            bytes("")
        );

        // weth was deposited, pool tokens were minted to Alice.
        assertEq(weth.balanceOf(alice), defaultBalance - ETH_AMOUNT_IN, "Wrong WETH balance");
        assertEq(wethPoolNoInit.balanceOf(alice), bptAmountOut, "Wrong WETH pool balance");
        assertGt(bptAmountOut, 0, "Wrong bptAmountOut");
    }

    function testInitializeNativeNoBalance() public {
        checkPreConditions();

        // Caller does not have enough ETH, even if they hold weth.
        vm.expectRevert(abi.encodeWithSelector(IRouter.InsufficientEth.selector));
        vm.prank(alice);
        router.initialize(
            address(wethPoolNoInit),
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            INIT_BPT,
            true,
            bytes("")
        );
    }

    function testInitializeNative() public {
        require(address(alice).balance == defaultBalance);
        require(wethPool.balanceOf(alice) == 0);

        bool wethIsEth = true;
        vm.startPrank(alice);
        uint256 bptAmountOut = router.initialize{ value: ETH_AMOUNT_IN }(
            address(wethPoolNoInit),
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            INIT_BPT,
            wethIsEth,
            bytes("")
        );

        // weth was deposited, pool tokens were minted to Alice.
        assertEq(address(alice).balance, defaultBalance - ETH_AMOUNT_IN, "Wrong ETH balance");
        assertEq(wethPoolNoInit.balanceOf(alice), bptAmountOut, "Wrong WETH pool balance");
        assertGt(bptAmountOut, 0);
    }

    function testInitializeNativeExcessEth() public {
        uint256 initExcessEth = defaultBalance + 1 ether;
        vm.deal(alice, initExcessEth);

        vm.startPrank(alice);
        uint256 aliceNativeBalanceBefore = address(alice).balance;
        require(aliceNativeBalanceBefore >= initExcessEth);
        require(wethPool.balanceOf(alice) == 0);

        bool wethIsEth = true;
        uint256 bptAmountOut = router.initialize{ value: initExcessEth }(
            address(wethPoolNoInit),
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            INIT_BPT,
            wethIsEth,
            bytes("")
        );

        // weth was deposited, excess ETH was returned, pool tokens were minted to Alice.
        assertEq(address(alice).balance, aliceNativeBalanceBefore - ETH_AMOUNT_IN);
        assertEq(wethPoolNoInit.balanceOf(alice), bptAmountOut);
        assertGt(bptAmountOut, 0);
    }

    function testAddLiquidityWETHNoBalance() public {
        checkPreConditions();

        // Revert when sending ETH while wethIsEth is false (caller holds no weth).
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, broke, 0, ETH_AMOUNT_IN)
        );
        vm.prank(broke);
        router.addLiquidityCustom(
            address(wethPool),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            BPT_AMOUNT_OUT,
            false,
            bytes("")
        );
    }

    function testAddLiquidityWETH() public {
        vm.prank(alice);
        snapStart("routerAddLiquidityWETH");
        router.addLiquidityCustom(
            address(wethPool),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            BPT_AMOUNT_OUT,
            false,
            bytes("")
        );
        snapEnd();

        // weth was deposited, pool tokens were minted to Alice.
        assertEq(defaultBalance - weth.balanceOf(alice), ETH_AMOUNT_IN);
        assertEq(wethPool.balanceOf(alice), BPT_AMOUNT_OUT);
    }

    function testAddLiquidityNativeNoBalance() public {
        checkPreConditions();

        // Caller does not have enough ETH, even if they hold weth.
        vm.expectRevert(abi.encodeWithSelector(IRouter.InsufficientEth.selector));
        vm.prank(alice);
        router.addLiquidityCustom(
            address(wethPool),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            BPT_AMOUNT_OUT,
            true,
            bytes("")
        );
    }

    function testAddLiquidityNative() public {
        checkPreConditions();

        snapStart("routerAddLiquidityNative");
        vm.prank(alice);
        router.addLiquidityCustom{ value: ETH_AMOUNT_IN }(
            address(wethPool),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            BPT_AMOUNT_OUT,
            true,
            bytes("")
        );
        snapEnd();

        // weth was deposited, pool tokens were minted to Alice.
        assertEq(address(alice).balance, defaultBalance - ETH_AMOUNT_IN);
        assertEq(wethPool.balanceOf(alice), BPT_AMOUNT_OUT);
    }

    function testAddLiquidityNativeExcessEth() public {
        require(address(alice).balance == defaultBalance);
        require(wethPool.balanceOf(alice) == 0);

        vm.prank(alice);
        router.addLiquidityCustom{ value: defaultBalance }(
            address(wethPool),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            BPT_AMOUNT_OUT,
            true,
            bytes("")
        );

        // weth was deposited, excess was returned, pool tokens were minted to Alice.
        assertEq(address(alice).balance, defaultBalance - ETH_AMOUNT_IN);
        assertEq(wethPool.balanceOf(alice), BPT_AMOUNT_OUT);
    }

    function testRemoveLiquidityWETH() public {
        // Make Alice an LP and remove its liquidity position afterwards
        vm.startPrank(alice);
        bool wethIsEth = true;
        uint256 exactBptAmount = BPT_AMOUNT_OUT;

        router.addLiquidityCustom{ value: ETH_AMOUNT_IN }(
            address(wethPool),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            exactBptAmount,
            wethIsEth,
            bytes("")
        );

        uint256 aliceNativeBalanceBefore = address(alice).balance;
        require(wethPool.balanceOf(alice) == exactBptAmount);
        require(weth.balanceOf(alice) == defaultBalance, "Wrong WETh balance");

        wethIsEth = false;
        snapStart("routerRemoveLiquidityWETH");
        router.removeLiquidityCustom(
            address(wethPool),
            exactBptAmount,
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            wethIsEth,
            ""
        );
        snapEnd();

        // Liquidity position was removed, Alice gets weth back
        assertEq(weth.balanceOf(alice), defaultBalance + ETH_AMOUNT_IN);
        assertEq(wethPool.balanceOf(alice), 0);
        assertEq(address(alice).balance, aliceNativeBalanceBefore);
    }

    function testRemoveLiquidityNative() public {
        // Make Alice an LP and remove its liquidity position afterwards
        vm.startPrank(alice);
        bool wethIsEth = true;
        uint256 exactBptAmount = BPT_AMOUNT_OUT;
        router.addLiquidityCustom{ value: ETH_AMOUNT_IN }(
            address(wethPool),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            exactBptAmount,
            wethIsEth,
            bytes("")
        );

        uint256 aliceNativeBalanceBefore = address(alice).balance;
        require(wethPool.balanceOf(alice) == exactBptAmount);
        require(weth.balanceOf(alice) == defaultBalance);

        snapStart("routerRemoveLiquidityNative");
        router.removeLiquidityCustom(
            address(wethPool),
            exactBptAmount,
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            wethIsEth,
            ""
        );
        snapEnd();

        // Liquidity position was removed, Alice gets ETH back
        assertEq(weth.balanceOf(alice), defaultBalance);
        assertEq(wethPool.balanceOf(alice), 0);
        assertEq(address(alice).balance, aliceNativeBalanceBefore + ETH_AMOUNT_IN);
    }

    function testSwapExactInWETH() public {
        require(weth.balanceOf(alice) == defaultBalance);

        bool wethIsEth = false;

        vm.prank(alice);
        snapStart("routerSwapExactInWETH");
        uint256 outputTokenAmount = router.swapExactIn(
            address(wethPool),
            weth,
            dai,
            ETH_AMOUNT_IN,
            0,
            type(uint256).max,
            wethIsEth,
            ""
        );
        snapEnd();

        assertEq(weth.balanceOf(alice), defaultBalance - ETH_AMOUNT_IN);
        assertEq(dai.balanceOf(alice), defaultBalance + outputTokenAmount);
    }

    function testSwapExactOutWETH() public {
        require(weth.balanceOf(alice) == defaultBalance);
        bool wethIsEth = false;

        vm.prank(alice);
        uint256 outputTokenAmount = router.swapExactOut(
            address(wethPool),
            weth,
            dai,
            DAI_AMOUNT_OUT,
            type(uint256).max,
            type(uint256).max,
            wethIsEth,
            ""
        );

        assertEq(weth.balanceOf(alice), defaultBalance - outputTokenAmount);
        assertEq(dai.balanceOf(alice), defaultBalance + DAI_AMOUNT_OUT);
    }

    function testSwapExactInNative() public {
        require(weth.balanceOf(alice) == defaultBalance);
        require(alice.balance == defaultBalance);

        bool wethIsEth = true;

        vm.prank(alice);
        snapStart("routerSwapExactInNative");
        router.swapExactIn{ value: ETH_AMOUNT_IN }(
            address(wethPool),
            weth,
            dai,
            ETH_AMOUNT_IN,
            0,
            type(uint256).max,
            wethIsEth,
            ""
        );
        snapEnd();

        assertEq(weth.balanceOf(alice), defaultBalance);
        assertEq(dai.balanceOf(alice), defaultBalance + ETH_AMOUNT_IN);
        assertEq(alice.balance, defaultBalance - ETH_AMOUNT_IN);
    }

    function testSwapExactOutNative() public {
        require(weth.balanceOf(alice) == defaultBalance);
        require(alice.balance == defaultBalance);

        bool wethIsEth = true;

        vm.prank(alice);
        router.swapExactOut{ value: DAI_AMOUNT_OUT }(
            address(wethPool),
            weth,
            dai,
            DAI_AMOUNT_OUT,
            type(uint256).max,
            type(uint256).max,
            wethIsEth,
            ""
        );

        assertEq(weth.balanceOf(alice), defaultBalance);
        assertEq(dai.balanceOf(alice), defaultBalance + DAI_AMOUNT_OUT);
        assertEq(alice.balance, defaultBalance - DAI_AMOUNT_OUT);
    }

    function testSwapNativeExcessEth() public {
        require(weth.balanceOf(alice) == defaultBalance);
        require(alice.balance == defaultBalance);

        bool wethIsEth = true;

        vm.startPrank(alice);
        router.swapExactIn{ value: defaultBalance }(
            address(wethPool),
            weth,
            dai,
            ETH_AMOUNT_IN,
            0,
            type(uint256).max,
            wethIsEth,
            ""
        );

        // Only ETH_AMOUNT_IN is sent to the router
        assertEq(weth.balanceOf(alice), defaultBalance);
        assertEq(dai.balanceOf(alice), defaultBalance + ETH_AMOUNT_IN);
        assertEq(alice.balance, defaultBalance - ETH_AMOUNT_IN);
    }

    function testGetSingleInputArray() public {
        uint256[] memory amountsGiven = router.getSingleInputArray(address(pool), dai, 1234);
        assertEq(amountsGiven.length, 2);
        assertEq(amountsGiven[0], 1234);
        assertEq(amountsGiven[1], 0);

        amountsGiven = router.getSingleInputArray(address(pool), usdc, 4321);
        assertEq(amountsGiven.length, 2);
        assertEq(amountsGiven[0], 0);
        assertEq(amountsGiven[1], 4321);

        vm.expectRevert(abi.encodeWithSelector(TokenNotRegistered.selector));
        router.getSingleInputArray(address(pool), weth, DAI_AMOUNT_IN);
    }

    function checkPreConditions() internal {
        require(weth.balanceOf(alice) == defaultBalance, "Wrong WETH balance");
        require(alice.balance == defaultBalance, "Wrong WETH balance");
        require(wethPool.balanceOf(alice) == 0, "Wrong weth pool balance");
    }
}
