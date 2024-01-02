// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";

import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

struct Balances {
    uint256[] userTokens;
    uint256 userBpt;
    uint256[] poolTokens;
}

contract VaultLiquidityTest is Test {
    using ArrayHelpers for *;

    VaultMock vault;
    Router router;
    BasicAuthorizerMock authorizer;
    PoolMock pool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant USDC_AMOUNT_IN = 1e3 * 1e6;
    uint256 constant DAI_AMOUNT_IN = 1e3 * 1e18;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), new WETHTestToken());
        USDC = new ERC20TestToken("USDC", "USDC", 6);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        IRateProvider[] memory rateProviders = new IRateProvider[](2);

        pool = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );

        USDC.mint(alice, USDC_AMOUNT_IN);
        DAI.mint(alice, DAI_AMOUNT_IN);
        USDC.mint(bob, USDC_AMOUNT_IN);
        DAI.mint(bob, DAI_AMOUNT_IN);

        vm.startPrank(alice);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.startPrank(bob);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(address(USDC), "USDC");
        vm.label(address(DAI), "DAI");
    }

    function testAddLiquidityUnbalanced() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        vm.startPrank(alice);

        Balances memory balancesBefore = _getBalances(alice);
        uint256[] memory amountsIn = [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray();

        uint256 bptAmountOut = router.addLiquidityUnbalanced(address(pool), amountsIn, DAI_AMOUNT_IN, false, bytes(""));
        vm.stopPrank();

        Balances memory balancesAfter = _getBalances(alice);

        _compareBalancesAddLiquidity(balancesBefore, balancesAfter, amountsIn, bptAmountOut);

        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, DAI_AMOUNT_IN * 2, "Invalid amount of BPT");
    }

    function testAddLiquiditySingleTokenExactOut() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        vm.startPrank(alice);

        Balances memory balancesBefore = _getBalances(alice);
        uint256 bptAmountOut = DAI_AMOUNT_IN;

        uint256[] memory amountsIn = router.addLiquiditySingleTokenExactOut(
            address(pool),
            DAI,
            DAI_AMOUNT_IN,
            bptAmountOut,
            false,
            bytes("")
        );
        vm.stopPrank();

        Balances memory balancesAfter = _getBalances(alice);

        _compareBalancesAddLiquidity(balancesBefore, balancesAfter, amountsIn, bptAmountOut);

        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, DAI_AMOUNT_IN);
    }

    function testAddLiquidityCustom() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        vm.startPrank(alice);

        Balances memory balancesBefore = _getBalances(alice);

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = router.addLiquidityCustom(
            address(pool),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            false,
            bytes("")
        );
        vm.stopPrank();

        Balances memory balancesAfter = _getBalances(alice);

        _compareBalancesAddLiquidity(balancesBefore, balancesAfter, amountsIn, bptAmountOut);

        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, DAI_AMOUNT_IN);
    }

    function testAddLiquidityNotInitialized() public {
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(IVault.PoolNotInitialized.selector, address(pool)));
        router.addLiquidityUnbalanced(
            address(pool),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            false,
            bytes("")
        );
    }

    function testRemoveLiquidityProportional() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        vm.startPrank(alice);

        router.addLiquidityUnbalanced(
            address(pool),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            false,
            bytes("")
        );

        Balances memory balancesBefore = _getBalances(alice);
        uint256 bptAmountIn = DAI_AMOUNT_IN * 2;

        uint256[] memory amountsOut = router.removeLiquidityProportional(
            address(pool),
            bptAmountIn,
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            false,
            bytes("")
        );

        vm.stopPrank();

        _compareBalancesRemoveLiquidity(balancesBefore, _getBalances(alice), bptAmountIn, amountsOut);

        // amountsOut are correct
        assertEq(amountsOut[0], DAI_AMOUNT_IN);
        assertEq(amountsOut[1], USDC_AMOUNT_IN);
    }

    function testRemoveLiquiditySingleTokenExactIn() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        vm.startPrank(alice);

        router.addLiquidityUnbalanced(
            address(pool),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            false,
            bytes("")
        );

        Balances memory balancesBefore = _getBalances(alice);
        uint256 bptAmountIn = DAI_AMOUNT_IN * 2;

        uint256[] memory amountsOut = router.removeLiquiditySingleTokenExactIn(
            address(pool),
            bptAmountIn,
            DAI,
            DAI_AMOUNT_IN,
            false,
            bytes("")
        );

        vm.stopPrank();

        _compareBalancesRemoveLiquidity(balancesBefore, _getBalances(alice), bptAmountIn, amountsOut);

        // amountsOut are correct
        assertEq(amountsOut[0], DAI_AMOUNT_IN);
        assertEq(amountsOut[1], 0);
    }

    function testRemoveLiquiditySingleTokenExactOut() public {
        _mockInitialize(bob);

        vm.startPrank(alice);

        router.addLiquidityUnbalanced(
            address(pool),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            false,
            bytes("")
        );

        Balances memory balancesBefore = _getBalances(alice);
        uint256[] memory amountsOut = [DAI_AMOUNT_IN * 2, 0].toMemoryArray();

        uint256 bptAmountIn = router.removeLiquiditySingleTokenExactOut(
            address(pool),
            DAI_AMOUNT_IN,
            DAI,
            uint256(2 * DAI_AMOUNT_IN),
            false,
            bytes("")
        );

        vm.stopPrank();

        _compareBalancesRemoveLiquidity(balancesBefore, _getBalances(alice), bptAmountIn, amountsOut);
    }

    function testRemoveLiquidityCustom() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        vm.startPrank(alice);

        router.addLiquidityUnbalanced(
            address(pool),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            false,
            bytes("")
        );

        Balances memory balancesBefore = _getBalances(alice);

        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = router.removeLiquidityCustom(
            address(pool),
            DAI_AMOUNT_IN * 2,
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            false,
            bytes("")
        );

        vm.stopPrank();

        _compareBalancesRemoveLiquidity(balancesBefore, _getBalances(alice), bptAmountIn, amountsOut);

        // amountsOut are correct
        assertEq(amountsOut[0], DAI_AMOUNT_IN);
        assertEq(amountsOut[1], USDC_AMOUNT_IN);
    }

    function testRemoveLiquidityNotInitialized() public {
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(IVault.PoolNotInitialized.selector, address(pool)));
        router.removeLiquidityProportional(
            address(pool),
            DAI_AMOUNT_IN,
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function _mockInitialize(address initializer) internal {
        vm.startPrank(initializer);

        // The mock pool can be initialized with no liquidity; it mints some BPT to the initializer
        // to comply with the vault's required minimum.
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [DAI_AMOUNT_IN, USDC_AMOUNT_IN].toMemoryArray(),
            0,
            false,
            bytes("")
        );
    }

    function _getBalances(address user) internal view returns (Balances memory balances) {
        balances.userTokens = new uint256[](2);

        balances.userTokens[0] = DAI.balanceOf(user);
        balances.userTokens[1] = USDC.balanceOf(user);
        balances.userBpt = pool.balanceOf(user);

        (, uint256[] memory poolBalances, , ) = vault.getPoolTokenInfo(address(pool));
        require(poolBalances[0] == DAI.balanceOf(address(vault)), "DAI pool balance does not match vault balance");
        require(poolBalances[1] == USDC.balanceOf(address(vault)), "USDC pool balance does not match vault balance");

        balances.poolTokens = poolBalances;
    }

    function _compareBalancesAddLiquidity(
        Balances memory balancesBefore,
        Balances memory balancesAfter,
        uint256[] memory amountsIn,
        uint256 bptAmountOut
    ) internal {
        // Tokens are transferred from the user to the vault
        assertEq(
            balancesAfter.userTokens[0],
            balancesBefore.userTokens[0] - amountsIn[0],
            "Add - User balance: token 0"
        );
        assertEq(
            balancesAfter.userTokens[1],
            balancesBefore.userTokens[1] - amountsIn[1],
            "Add - User balance: token 1"
        );

        // Tokens are now in the vault / pool
        assertEq(
            balancesAfter.poolTokens[0],
            balancesBefore.poolTokens[0] + amountsIn[0],
            "Add - Pool balance: token 0"
        );
        assertEq(
            balancesAfter.poolTokens[1],
            balancesBefore.poolTokens[1] + amountsIn[1],
            "Add - Pool balance: token 1"
        );

        // User now has BPT
        assertEq(balancesBefore.userBpt, 0, "Add - User BPT balance before");
        assertEq(balancesAfter.userBpt, bptAmountOut, "Add - User BPT balance after");
    }

    function _compareBalancesRemoveLiquidity(
        Balances memory balancesBefore,
        Balances memory balancesAfter,
        uint256 bptAmountIn,
        uint256[] memory amountsOut
    ) internal {
        // Tokens are transferred back to user
        assertEq(
            balancesAfter.userTokens[0],
            balancesBefore.userTokens[0] + amountsOut[0],
            "Remove - User balance: token 0"
        );
        assertEq(
            balancesAfter.userTokens[1],
            balancesBefore.userTokens[1] + amountsOut[1],
            "Remove - User balance: token 1"
        );

        // Tokens are no longer in the vault / pool
        assertEq(
            balancesAfter.poolTokens[0],
            balancesBefore.poolTokens[0] - amountsOut[0],
            "Remove - Pool balance: token 0"
        );
        assertEq(
            balancesAfter.poolTokens[1],
            balancesBefore.poolTokens[1] - amountsOut[1],
            "Remove - Pool balance: token 1"
        );

        // User has burnt the correct amount of BPT
        assertEq(balancesBefore.userBpt, bptAmountIn, "Remove - User BPT balance before");
        assertEq(balancesAfter.userBpt, 0, "Remove - User BPT balance after");
    }
}
