// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
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
import { RouterMock } from "../../contracts/test/RouterMock.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";
import { VaultExtensionMock } from "../../contracts/test/VaultExtensionMock.sol";

contract RouterTest is Test {
    using ArrayHelpers for *;

    VaultMock vault;
    VaultExtensionMock vaultExtension;
    IRouter router;
    RouterMock routerMock;
    BasicAuthorizerMock authorizer;
    PoolMock pool;
    PoolMock wethPool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    WETHTestToken WETH;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant USDC_AMOUNT_IN = 1e3 * 1e6;
    uint256 constant DAI_AMOUNT_IN = 1e3 * 1e18;
    uint256 constant DAI_AMOUNT_OUT = 1e2 * 1e18;
    uint256 constant ETH_AMOUNT_IN = 1e3 ether;
    uint256 constant INIT_BPT = 10e18;
    uint256 constant BPT_AMOUNT_OUT = 1e18;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vaultExtension = new VaultExtensionMock();
        vault = new VaultMock(vaultExtension, authorizer, 30 days, 90 days);
        WETH = new WETHTestToken();
        router = new Router(IVault(address(vault)), WETH);
        routerMock = new RouterMock(IVault(address(vault)), WETH);
        USDC = new ERC20TestToken("USDC", "USDC", 6);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        IRateProvider[] memory rateProviders = new IRateProvider[](2);

        pool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );
        wethPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 WETH Pool",
            "ERC20POOL",
            [address(WETH), address(DAI)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );

        USDC.mint(bob, USDC_AMOUNT_IN);
        DAI.mint(bob, DAI_AMOUNT_IN);
        vm.deal(bob, ETH_AMOUNT_IN);

        USDC.mint(alice, USDC_AMOUNT_IN);
        DAI.mint(alice, DAI_AMOUNT_IN);
        vm.deal(alice, ETH_AMOUNT_IN);

        vm.startPrank(bob);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);
        WETH.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.startPrank(alice);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);
        WETH.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(address(USDC), "USDC");
        vm.label(address(DAI), "DAI");
    }

    function testQuerySwap() public {
        vm.prank(alice);
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            INIT_BPT,
            false,
            bytes("")
        );

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(EVMCallModeHelpers.NotStaticCall.selector));
        router.querySwapExactIn(address(pool), USDC, DAI, USDC_AMOUNT_IN, bytes(""));
    }

    function testDisableQueries() public {
        vm.prank(alice);
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            INIT_BPT,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));

        vault.disableQuery();

        // Authorize alice
        bytes32 disableQueryRole = vault.getActionId(IVaultMain.disableQuery.selector);

        authorizer.grantRole(disableQueryRole, alice);

        vm.prank(alice);
        vault.disableQuery();

        vm.expectRevert(abi.encodeWithSelector(IVaultMain.QueriesDisabled.selector));

        vm.prank(address(0), address(0));
        router.querySwapExactIn(address(pool), USDC, DAI, USDC_AMOUNT_IN, bytes(""));
    }

    function testInitializeBelowMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20MultiToken.TotalSupplyTooLow.selector, 0, 1e6));
        router.initialize(
            address(wethPool),
            [address(WETH), address(DAI)].toMemoryArray().asIERC20(),
            [uint256(0), uint256(0)].toMemoryArray(),
            uint256(0),
            false,
            bytes("")
        );
    }

    function testInitializeWETHNoBalance() public {
        require(WETH.balanceOf(alice) == 0);

        vm.prank(alice);
        bool wethIsEth = false;
        // Revert when sending ETH while wethIsEth is false (caller holds no WETH).
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, ETH_AMOUNT_IN)
        );
        router.initialize{ value: ETH_AMOUNT_IN }(
            address(wethPool),
            [address(WETH), address(DAI)].toMemoryArray().asIERC20(),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            INIT_BPT,
            wethIsEth,
            bytes("")
        );
    }

    function testInitializeWETH() public {
        vm.startPrank(alice);
        WETH.deposit{ value: ETH_AMOUNT_IN }();
        // Alice holds WETH, but no pool tokens.
        require(WETH.balanceOf(alice) == ETH_AMOUNT_IN);
        require(wethPool.balanceOf(alice) == 0);

        bool wethIsEth = false;
        uint256 bptAmountOut = router.initialize(
            address(wethPool),
            [address(WETH), address(DAI)].toMemoryArray().asIERC20(),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            INIT_BPT,
            wethIsEth,
            bytes("")
        );

        // WETH was deposited, pool tokens were minted to Alice.
        assertEq(WETH.balanceOf(alice), 0);
        assertEq(wethPool.balanceOf(alice), bptAmountOut);
        assertGt(bptAmountOut, 0);
    }

    function testInitializeNativeNoBalance() public {
        vm.startPrank(alice);
        WETH.deposit{ value: ETH_AMOUNT_IN }();
        require(WETH.balanceOf(alice) == ETH_AMOUNT_IN);
        require(alice.balance < ETH_AMOUNT_IN);
        require(wethPool.balanceOf(alice) == 0);

        bool wethIsEth = true;
        // Caller does not have enough ETH, even if they hold WETH.
        vm.expectRevert(abi.encodeWithSelector(IRouter.InsufficientEth.selector));
        router.initialize(
            address(wethPool),
            [address(WETH), address(DAI)].toMemoryArray().asIERC20(),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            INIT_BPT,
            wethIsEth,
            bytes("")
        );
    }

    function testInitializeNative() public {
        vm.startPrank(alice);
        uint256 aliceNativeBalanceBefore = address(alice).balance;
        require(aliceNativeBalanceBefore >= ETH_AMOUNT_IN);
        require(wethPool.balanceOf(alice) == 0);

        bool wethIsEth = true;
        uint256 bptAmountOut = router.initialize{ value: ETH_AMOUNT_IN }(
            address(wethPool),
            [address(WETH), address(DAI)].toMemoryArray().asIERC20(),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            INIT_BPT,
            wethIsEth,
            bytes("")
        );

        // WETH was deposited, pool tokens were minted to Alice.
        assertEq(address(alice).balance, aliceNativeBalanceBefore - ETH_AMOUNT_IN);
        assertEq(wethPool.balanceOf(alice), bptAmountOut);
        assertGt(bptAmountOut, 0);
    }

    function testInitializeNativeExcessEth() public {
        uint256 initExcessEth = ETH_AMOUNT_IN + 1 ether;
        vm.deal(alice, initExcessEth);

        vm.startPrank(alice);
        uint256 aliceNativeBalanceBefore = address(alice).balance;
        require(aliceNativeBalanceBefore >= initExcessEth);
        require(wethPool.balanceOf(alice) == 0);

        bool wethIsEth = true;
        uint256 bptAmountOut = router.initialize{ value: initExcessEth }(
            address(wethPool),
            [address(WETH), address(DAI)].toMemoryArray().asIERC20(),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            INIT_BPT,
            wethIsEth,
            bytes("")
        );

        // WETH was deposited, excess ETH was returned, pool tokens were minted to Alice.
        assertEq(address(alice).balance, aliceNativeBalanceBefore - ETH_AMOUNT_IN);
        assertEq(wethPool.balanceOf(alice), bptAmountOut);
        assertGt(bptAmountOut, 0);
    }

    function testAddLiquidityWETHNoBalance() public {
        _initializePool();

        bool wethIsEth = false;
        vm.startPrank(alice);
        require(WETH.balanceOf(alice) == 0);

        // Revert when sending ETH while wethIsEth is false (caller holds no WETH).
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, ETH_AMOUNT_IN)
        );
        router.addLiquidityCustom(
            address(wethPool),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            BPT_AMOUNT_OUT,
            wethIsEth,
            bytes("")
        );
    }

    function testAddLiquidityWETH() public {
        _initializePool();
        bool wethIsEth = false;

        vm.startPrank(alice);
        WETH.deposit{ value: ETH_AMOUNT_IN }();
        require(WETH.balanceOf(alice) == ETH_AMOUNT_IN);
        require(wethPool.balanceOf(alice) == 0);

        router.addLiquidityCustom(
            address(wethPool),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            BPT_AMOUNT_OUT,
            wethIsEth,
            bytes("")
        );

        // WETH was deposited, pool tokens were minted to Alice.
        assertEq(WETH.balanceOf(alice), 0);
        assertEq(wethPool.balanceOf(alice), BPT_AMOUNT_OUT);
    }

    function testAddLiquidityNativeNoBalance() public {
        _initializePool();
        bool wethIsEth = true;

        vm.startPrank(alice);
        WETH.deposit{ value: ETH_AMOUNT_IN }();
        require(WETH.balanceOf(alice) == ETH_AMOUNT_IN);
        require(alice.balance < ETH_AMOUNT_IN);
        require(wethPool.balanceOf(alice) == 0);

        // Caller does not have enough ETH, even if they hold WETH.
        vm.expectRevert(abi.encodeWithSelector(IRouter.InsufficientEth.selector));
        router.addLiquidityCustom(
            address(wethPool),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            BPT_AMOUNT_OUT,
            wethIsEth,
            bytes("")
        );
    }

    function testAddLiquidityNative() public {
        _initializePool();
        bool wethIsEth = true;

        vm.startPrank(alice);
        uint256 aliceNativeBalanceBefore = address(alice).balance;
        require(aliceNativeBalanceBefore >= ETH_AMOUNT_IN);
        require(wethPool.balanceOf(alice) == 0);

        router.addLiquidityCustom{ value: ETH_AMOUNT_IN }(
            address(wethPool),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            BPT_AMOUNT_OUT,
            wethIsEth,
            bytes("")
        );

        // WETH was deposited, pool tokens were minted to Alice.
        assertEq(address(alice).balance, aliceNativeBalanceBefore - ETH_AMOUNT_IN);
        assertEq(wethPool.balanceOf(alice), BPT_AMOUNT_OUT);
    }

    function testAddLiquidityNativeExcessEth() public {
        _initializePool();
        uint256 ethAmountInExcess = ETH_AMOUNT_IN + 1 ether;
        vm.deal(alice, ethAmountInExcess);
        bool wethIsEth = true;

        vm.startPrank(alice);
        uint256 aliceNativeBalanceBefore = address(alice).balance;
        require(aliceNativeBalanceBefore >= ethAmountInExcess);
        require(wethPool.balanceOf(alice) == 0);

        router.addLiquidityCustom{ value: ethAmountInExcess }(
            address(wethPool),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            BPT_AMOUNT_OUT,
            wethIsEth,
            bytes("")
        );

        // WETH was deposited, excess was returned, pool tokens were minted to Alice.
        assertEq(address(alice).balance, aliceNativeBalanceBefore - ETH_AMOUNT_IN);
        assertEq(wethPool.balanceOf(alice), BPT_AMOUNT_OUT);
    }

    function testRemoveLiquidityWETH() public {
        _initializePool();
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
        require(WETH.balanceOf(alice) == 0);

        wethIsEth = false;
        router.removeLiquidityCustom(
            address(wethPool),
            exactBptAmount,
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            wethIsEth,
            ""
        );

        // Liquidity position was removed, Alice gets WETH back
        assertGt(WETH.balanceOf(alice), 0);
        assertEq(WETH.balanceOf(alice), ETH_AMOUNT_IN);
        assertEq(wethPool.balanceOf(alice), 0);
        assertEq(address(alice).balance, aliceNativeBalanceBefore);
    }

    function testRemoveLiquidityNative() public {
        _initializePool();
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
        require(WETH.balanceOf(alice) == 0);

        router.removeLiquidityCustom(
            address(wethPool),
            exactBptAmount,
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            wethIsEth,
            ""
        );

        // Liquidity position was removed, Alice gets ETH back
        assertEq(WETH.balanceOf(alice), 0);
        assertEq(wethPool.balanceOf(alice), 0);
        assertEq(address(alice).balance, aliceNativeBalanceBefore + ETH_AMOUNT_IN);
    }

    function testSwapExactInWETH() public {
        _initializePool();
        vm.startPrank(alice);
        WETH.deposit{ value: ETH_AMOUNT_IN }();

        require(WETH.balanceOf(alice) == ETH_AMOUNT_IN);
        uint256 daiBalanceBefore = DAI.balanceOf(alice);
        bool wethIsEth = false;

        uint256 outputTokenAmount = router.swapExactIn(
            address(wethPool),
            WETH,
            DAI,
            ETH_AMOUNT_IN,
            0,
            type(uint256).max,
            wethIsEth,
            ""
        );

        assertEq(WETH.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(alice), daiBalanceBefore + outputTokenAmount);
    }

    function testSwapExactOutWETH() public {
        _initializePool();
        vm.startPrank(alice);
        WETH.deposit{ value: ETH_AMOUNT_IN }();

        require(WETH.balanceOf(alice) == ETH_AMOUNT_IN);
        uint256 daiBalanceBefore = DAI.balanceOf(alice);
        bool wethIsEth = false;

        uint256 outputTokenAmount = router.swapExactOut(
            address(wethPool),
            WETH,
            DAI,
            DAI_AMOUNT_OUT,
            type(uint256).max,
            type(uint256).max,
            wethIsEth,
            ""
        );

        assertEq(WETH.balanceOf(alice), ETH_AMOUNT_IN - outputTokenAmount);
        assertEq(DAI.balanceOf(alice), daiBalanceBefore + DAI_AMOUNT_OUT);
    }

    function testSwapExactInNative() public {
        _initializePool();
        vm.startPrank(alice);

        require(WETH.balanceOf(alice) == 0);
        require(alice.balance >= ETH_AMOUNT_IN);
        uint256 ethBalanceBefore = alice.balance;
        uint256 daiBalanceBefore = DAI.balanceOf(alice);
        bool wethIsEth = true;

        router.swapExactIn{ value: ETH_AMOUNT_IN }(
            address(wethPool),
            WETH,
            DAI,
            ETH_AMOUNT_IN,
            0,
            type(uint256).max,
            wethIsEth,
            ""
        );

        assertEq(WETH.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(alice), daiBalanceBefore + ETH_AMOUNT_IN);
        assertEq(alice.balance, ethBalanceBefore - ETH_AMOUNT_IN);
    }

    function testSwapExactOutNative() public {
        _initializePool();
        vm.startPrank(alice);

        require(WETH.balanceOf(alice) == 0);
        require(alice.balance >= ETH_AMOUNT_IN);
        uint256 daiBalanceBefore = DAI.balanceOf(alice);
        uint256 ethBalanceBefore = alice.balance;
        bool wethIsEth = true;

        router.swapExactOut{ value: DAI_AMOUNT_OUT }(
            address(wethPool),
            WETH,
            DAI,
            DAI_AMOUNT_OUT,
            type(uint256).max,
            type(uint256).max,
            wethIsEth,
            ""
        );

        assertEq(WETH.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(alice), daiBalanceBefore + DAI_AMOUNT_OUT);
        assertEq(alice.balance, ethBalanceBefore - DAI_AMOUNT_OUT);
    }

    function testSwapNativeExcessEth() public {
        _initializePool();
        uint256 excessEthAmountIn = ETH_AMOUNT_IN + 1 ether;
        vm.deal(alice, excessEthAmountIn);

        vm.startPrank(alice);

        require(WETH.balanceOf(alice) == 0);
        require(alice.balance >= ETH_AMOUNT_IN);
        uint256 ethBalanceBefore = alice.balance;
        uint256 daiBalanceBefore = DAI.balanceOf(alice);
        bool wethIsEth = true;

        router.swapExactIn{ value: excessEthAmountIn }(
            address(wethPool),
            WETH,
            DAI,
            ETH_AMOUNT_IN,
            0,
            type(uint256).max,
            wethIsEth,
            ""
        );

        // Only ETH_AMOUNT_IN is sent to the router
        assertEq(WETH.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(alice), daiBalanceBefore + ETH_AMOUNT_IN);
        assertEq(alice.balance, ethBalanceBefore - ETH_AMOUNT_IN);
    }

    function testGetSingleInputArray() public {
        uint256[] memory amountsGiven = routerMock.getSingleInputArray(address(pool), DAI, 1234);
        assertEq(amountsGiven.length, 2);
        assertEq(amountsGiven[0], 1234);
        assertEq(amountsGiven[1], 0);

        amountsGiven = routerMock.getSingleInputArray(address(pool), USDC, 4321);
        assertEq(amountsGiven.length, 2);
        assertEq(amountsGiven[0], 0);
        assertEq(amountsGiven[1], 4321);

        vm.expectRevert(abi.encodeWithSelector(IVaultMain.TokenNotRegistered.selector));
        routerMock.getSingleInputArray(address(pool), WETH, DAI_AMOUNT_IN);
    }

    function _initializePool() internal returns (uint256 bptAmountOut) {
        vm.prank(bob);
        bool wethIsEth = true;
        bptAmountOut = router.initialize{ value: ETH_AMOUNT_IN }(
            address(wethPool),
            [address(WETH), address(DAI)].toMemoryArray().asIERC20(),
            [uint256(ETH_AMOUNT_IN), uint256(DAI_AMOUNT_IN)].toMemoryArray(),
            INIT_BPT,
            wethIsEth,
            bytes("")
        );
    }
}
