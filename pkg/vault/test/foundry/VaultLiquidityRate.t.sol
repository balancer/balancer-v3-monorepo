// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { ERC20PoolMock } from "../../contracts/test/ERC20PoolMock.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

struct Balances {
    uint256[] userTokens;
    uint256 userBpt;
    uint256[] poolTokens;
}

contract VaultLiquidityWithRatesTest is Test {
    using AssetHelpers for address[];
    using AssetHelpers for address[];
    using ArrayHelpers for address[2];
    using ArrayHelpers for uint256[2];

    VaultMock vault;
    Router router;
    BasicAuthorizerMock authorizer;
    RateProviderMock rateProvider;
    ERC20PoolMock pool;
    ERC20TestToken WSTETH;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    // Tokens are 18-decimal here, to isolate rates
    uint256 constant WSTETH_AMOUNT_IN = 1e3 * 1e18;
    uint256 constant DAI_AMOUNT_IN = 1e3 * 1e18;

    uint256 constant MOCK_RATE = 2e18;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), address(0));
        WSTETH = new ERC20TestToken("WSTETH", "WSTETH", 18);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProvider = new RateProviderMock();
        rateProviders[0] = rateProvider;

        pool = new ERC20PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(WSTETH)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );

        WSTETH.mint(alice, WSTETH_AMOUNT_IN);
        DAI.mint(alice, DAI_AMOUNT_IN);
        WSTETH.mint(bob, WSTETH_AMOUNT_IN);
        DAI.mint(bob, DAI_AMOUNT_IN);

        vm.startPrank(alice);

        WSTETH.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.startPrank(bob);

        WSTETH.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(address(WSTETH), "WSTETH");
        vm.label(address(DAI), "DAI");
    }

    function testAddLiquidityProportionalWithRate() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        rateProvider.mockRate(MOCK_RATE);

        vm.startPrank(alice);

        Balances memory balancesBefore = _getBalances(alice);

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = router.addLiquidity(
            address(pool),
            [address(DAI), address(WSTETH)].toMemoryArray().asAsset(),
            [DAI_AMOUNT_IN, WSTETH_AMOUNT_IN].toMemoryArray(),
            DAI_AMOUNT_IN,
            IVault.AddLiquidityKind.PROPORTIONAL,
            bytes("")
        );
        vm.stopPrank();

        Balances memory balancesAfter = _getBalances(alice);

        _compareBalancesAddLiquidity(balancesBefore, balancesAfter, amountsIn, bptAmountOut);

        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, DAI_AMOUNT_IN);
    }

    function testAddLiquidityUnbalancedWithRate() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        rateProvider.mockRate(MOCK_RATE);

        vm.startPrank(alice);

        Balances memory balancesBefore = _getBalances(alice);

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = router.addLiquidity(
            address(pool),
            [address(DAI), address(WSTETH)].toMemoryArray().asAsset(),
            [DAI_AMOUNT_IN, WSTETH_AMOUNT_IN].toMemoryArray(),
            DAI_AMOUNT_IN,
            IVault.AddLiquidityKind.UNBALANCED,
            bytes("")
        );
        vm.stopPrank();

        Balances memory balancesAfter = _getBalances(alice);

        _compareBalancesAddLiquidity(balancesBefore, balancesAfter, amountsIn, bptAmountOut);

        // ERC20PoolMock returns amountsIn[0], which is upscaled when calling the pool,
        // so the BPT amount should go down by the rate (raw balances unchanged)

        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, FixedPoint.mulDown(DAI_AMOUNT_IN, MOCK_RATE));
    }

    function testAddLiquiditySingleTokenExactOutWithRate() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        rateProvider.mockRate(MOCK_RATE);

        vm.startPrank(alice);

        Balances memory balancesBefore = _getBalances(alice);

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = router.addLiquidity(
            address(pool),
            [address(DAI), address(WSTETH)].toMemoryArray().asAsset(),
            [DAI_AMOUNT_IN, 0].toMemoryArray(),
            DAI_AMOUNT_IN,
            IVault.AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
            bytes("")
        );
        vm.stopPrank();

        Balances memory balancesAfter = _getBalances(alice);

        _compareBalancesAddLiquidity(balancesBefore, balancesAfter, amountsIn, bptAmountOut);

        // ERC20PoolMock returns the sender's balance of tokenIn (raw)

        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, DAI_AMOUNT_IN);
    }

    function testAddLiquidityCustomWithRate() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        rateProvider.mockRate(MOCK_RATE);

        vm.startPrank(alice);

        Balances memory balancesBefore = _getBalances(alice);

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = router.addLiquidity(
            address(pool),
            [address(DAI), address(WSTETH)].toMemoryArray().asAsset(),
            [DAI_AMOUNT_IN, WSTETH_AMOUNT_IN].toMemoryArray(),
            DAI_AMOUNT_IN,
            IVault.AddLiquidityKind.CUSTOM,
            bytes("")
        );
        vm.stopPrank();

        Balances memory balancesAfter = _getBalances(alice);

        _compareBalancesAddLiquidity(balancesBefore, balancesAfter, amountsIn, bptAmountOut);

        // ERC20PoolMock returns minBptAmountOut as the amountOut

        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, DAI_AMOUNT_IN);
    }

    function testRemoveLiquidityProportionalWithRate() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        rateProvider.mockRate(MOCK_RATE);

        vm.startPrank(alice);

        router.addLiquidity(
            address(pool),
            [address(DAI), address(WSTETH)].toMemoryArray().asAsset(),
            [DAI_AMOUNT_IN, WSTETH_AMOUNT_IN].toMemoryArray(),
            DAI_AMOUNT_IN,
            IVault.AddLiquidityKind.PROPORTIONAL,
            bytes("")
        );

        Balances memory balancesBefore = _getBalances(alice);

        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = router.removeLiquidity(
            address(pool),
            [address(DAI), address(WSTETH)].toMemoryArray().asAsset(),
            DAI_AMOUNT_IN,
            [DAI_AMOUNT_IN, WSTETH_AMOUNT_IN].toMemoryArray(),
            IVault.RemoveLiquidityKind.PROPORTIONAL,
            bytes("")
        );

        vm.stopPrank();

        Balances memory balancesAfter = _getBalances(alice);

        _compareBalancesRemoveLiquidity(balancesBefore, balancesAfter, bptAmountIn, bptAmountIn, amountsOut);

        // amountsOut are correct
        assertEq(amountsOut[0], DAI_AMOUNT_IN);
        assertEq(amountsOut[1], WSTETH_AMOUNT_IN);
    }

    function testRemoveLiquiditySingleTokenExactInWithRate() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        rateProvider.mockRate(MOCK_RATE);

        vm.startPrank(alice);

        router.addLiquidity(
            address(pool),
            [address(DAI), address(WSTETH)].toMemoryArray().asAsset(),
            [DAI_AMOUNT_IN, WSTETH_AMOUNT_IN].toMemoryArray(),
            DAI_AMOUNT_IN,
            IVault.AddLiquidityKind.UNBALANCED,
            bytes("")
        );

        Balances memory balancesBefore = _getBalances(alice);

        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = router.removeLiquidity(
            address(pool),
            [address(DAI), address(WSTETH)].toMemoryArray().asAsset(),
            DAI_AMOUNT_IN,
            [DAI_AMOUNT_IN, 0].toMemoryArray(),
            IVault.RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
            bytes("")
        );

        vm.stopPrank();

        Balances memory balancesAfter = _getBalances(alice);

        // ERC20PoolMock returns the current (upscaled) balance of tokenOut as amountOut,
        // so we need to multiply by the rate

        _compareBalancesRemoveLiquidity(
            balancesBefore,
            balancesAfter,
            FixedPoint.mulDown(bptAmountIn, MOCK_RATE),
            bptAmountIn,
            amountsOut
        );

        // amountsOut are correct (takes out initial liquidity as well)
        assertEq(amountsOut[0], DAI_AMOUNT_IN * 2);
        assertEq(amountsOut[1], 0);
    }

    function testRemoveLiquiditySingleTokenExactOutWithRate() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        rateProvider.mockRate(MOCK_RATE);

        vm.startPrank(alice);

        router.addLiquidity(
            address(pool),
            [address(DAI), address(WSTETH)].toMemoryArray().asAsset(),
            [DAI_AMOUNT_IN, WSTETH_AMOUNT_IN].toMemoryArray(),
            DAI_AMOUNT_IN,
            IVault.AddLiquidityKind.PROPORTIONAL,
            bytes("")
        );

        Balances memory balancesBefore = _getBalances(alice);

        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = router.removeLiquidity(
            address(pool),
            [address(DAI), address(WSTETH)].toMemoryArray().asAsset(),
            DAI_AMOUNT_IN,
            [DAI_AMOUNT_IN, 0].toMemoryArray(),
            IVault.RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
            bytes("")
        );

        vm.stopPrank();

        Balances memory balancesAfter = _getBalances(alice);

        // ERC20PoolMock returns the (raw) BPT balance of the sender for BPTIn

        _compareBalancesRemoveLiquidity(balancesBefore, balancesAfter, bptAmountIn, bptAmountIn, amountsOut);

        // amountsOut are correct
        assertEq(amountsOut[0], DAI_AMOUNT_IN);
        assertEq(amountsOut[1], 0);
    }

    function testRemoveLiquidityCustomWithRate() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        rateProvider.mockRate(MOCK_RATE);

        vm.startPrank(alice);

        router.addLiquidity(
            address(pool),
            [address(DAI), address(WSTETH)].toMemoryArray().asAsset(),
            [DAI_AMOUNT_IN, WSTETH_AMOUNT_IN].toMemoryArray(),
            DAI_AMOUNT_IN,
            IVault.AddLiquidityKind.UNBALANCED,
            bytes("")
        );

        Balances memory balancesBefore = _getBalances(alice);

        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = router.removeLiquidity(
            address(pool),
            [address(DAI), address(WSTETH)].toMemoryArray().asAsset(),
            DAI_AMOUNT_IN,
            [DAI_AMOUNT_IN, WSTETH_AMOUNT_IN].toMemoryArray(),
            IVault.RemoveLiquidityKind.CUSTOM,
            bytes("")
        );

        vm.stopPrank();

        Balances memory balancesAfter = _getBalances(alice);

        // ERC20PoolMock returns (upscaled) balances for amountsOut, so need to multiply by the rate.

        _compareBalancesRemoveLiquidity(
            balancesBefore,
            balancesAfter,
            FixedPoint.mulDown(bptAmountIn, MOCK_RATE),
            bptAmountIn,
            amountsOut
        );

        // amountsOut are correct
        assertEq(amountsOut[0], DAI_AMOUNT_IN);
        assertEq(amountsOut[1], WSTETH_AMOUNT_IN);
    }

    function _mockInitialize(address initializer) internal {
        vm.startPrank(initializer);

        // The mock pool can be initialized with no liquidity; it mints some BPT to the initializer
        // to comply with the vault's required minimum.
        router.initialize(
            address(pool),
            [address(DAI), address(WSTETH)].toMemoryArray().asAsset(),
            [DAI_AMOUNT_IN, WSTETH_AMOUNT_IN].toMemoryArray(),
            0,
            bytes("")
        );
    }

    function _getBalances(address user) internal view returns (Balances memory balances) {
        balances.userTokens = new uint256[](2);

        balances.userTokens[0] = DAI.balanceOf(user);
        balances.userTokens[1] = WSTETH.balanceOf(user);
        balances.userBpt = pool.balanceOf(user);

        (, uint256[] memory poolBalances, , ) = vault.getPoolTokenInfo(address(pool));
        require(poolBalances[0] == DAI.balanceOf(address(vault)), "DAI pool balance does not match vault balance");
        require(
            poolBalances[1] == WSTETH.balanceOf(address(vault)),
            "WSTETH pool balance does not match vault balance"
        );

        balances.poolTokens = poolBalances;
    }

    function _compareBalancesAddLiquidity(
        Balances memory balancesBefore,
        Balances memory balancesAfter,
        uint256[] memory amountsIn,
        uint256 bptAmountOut
    ) internal {
        // Assets are transferred from the user to the vault
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

        // Assets are now in the vault / pool
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
        uint256 rawBptAmountIn,
        uint256[] memory amountsOut
    ) internal {
        // Assets are transferred back to user
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

        // Assets are no longer in the vault / pool
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
        // Assumes rate >= 1
        assertEq(balancesAfter.userBpt, bptAmountIn - rawBptAmountIn, "Remove - User BPT balance after");
    }
}
