// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault, PoolData, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
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
import { PoolMock } from "../../contracts/test/PoolMock.sol";
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
    PoolMock pool;
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

        pool = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(WSTETH), address(DAI)].toMemoryArray().asIERC20(),
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

    function testAddLiquiditySingleTokenExactOutWithRate() public {
        _mockInitialize(bob);

        rateProvider.mockRate(MOCK_RATE);

        vm.startPrank(alice);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.calcBalance.selector,
                [FixedPoint.mulDown(WSTETH_AMOUNT_IN, MOCK_RATE), DAI_AMOUNT_IN].toMemoryArray(), // liveBalancesScaled18
                0,
                2e18 // 200% growth
            )
        );

        router.addLiquidity(
            address(pool),
            [address(WSTETH), address(DAI)].toMemoryArray().asAsset(),
            [WSTETH_AMOUNT_IN, 0].toMemoryArray(),
            WSTETH_AMOUNT_IN,
            IVault.AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
            bytes("")
        );
    }

    function testAddLiquidityCustomWithRate() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        rateProvider.mockRate(MOCK_RATE);

        uint256 rateAdjustedAmount = FixedPoint.mulDown(WSTETH_AMOUNT_IN, MOCK_RATE);

        vm.startPrank(alice);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onAddLiquidityCustom.selector,
                alice,
                [rateAdjustedAmount, DAI_AMOUNT_IN].toMemoryArray(), // maxAmountsIn
                WSTETH_AMOUNT_IN, // minBptOut
                [rateAdjustedAmount, DAI_AMOUNT_IN].toMemoryArray(), // liveBalancesScaled18
                bytes("")
            )
        );

        router.addLiquidity(
            address(pool),
            [address(WSTETH), address(DAI)].toMemoryArray().asAsset(),
            [WSTETH_AMOUNT_IN, DAI_AMOUNT_IN].toMemoryArray(),
            WSTETH_AMOUNT_IN,
            IVault.AddLiquidityKind.CUSTOM,
            bytes("")
        );
    }

    function testRemoveLiquidityProportionalWithRate() public {
        _mockInitialize(bob);

        rateProvider.mockRate(MOCK_RATE);

        vm.startPrank(alice);

        router.addLiquidity(
            address(pool),
            [address(WSTETH), address(DAI)].toMemoryArray().asAsset(),
            [WSTETH_AMOUNT_IN, DAI_AMOUNT_IN].toMemoryArray(),
            WSTETH_AMOUNT_IN,
            IVault.AddLiquidityKind.UNBALANCED,
            bytes("")
        );

        // TODO: Find a way to test rates inside the Vault
        router.removeLiquidity(
            address(pool),
            [address(WSTETH), address(DAI)].toMemoryArray().asAsset(),
            WSTETH_AMOUNT_IN,
            [WSTETH_AMOUNT_IN, DAI_AMOUNT_IN].toMemoryArray(),
            IVault.RemoveLiquidityKind.PROPORTIONAL,
            bytes("")
        );

        vm.stopPrank();
    }

    function testRemoveLiquiditySingleTokenExactInWithRate() public {
        _mockInitialize(bob);

        rateProvider.mockRate(MOCK_RATE);

        vm.startPrank(alice);

        router.addLiquidity(
            address(pool),
            [address(WSTETH), address(DAI)].toMemoryArray().asAsset(),
            [WSTETH_AMOUNT_IN, DAI_AMOUNT_IN].toMemoryArray(),
            WSTETH_AMOUNT_IN,
            IVault.AddLiquidityKind.UNBALANCED,
            bytes("")
        );

        PoolData memory startingBalances = vault.getPoolData(address(pool), Rounding.ROUND_DOWN);

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.calcBalance.selector,
                [startingBalances.balancesLiveScaled18[0], startingBalances.balancesLiveScaled18[1]].toMemoryArray(),
                0, // tokenOutIndex
                50e16 // invariantRatio
            )
        );

        router.removeLiquidity(
            address(pool),
            [address(WSTETH), address(DAI)].toMemoryArray().asAsset(),
            WSTETH_AMOUNT_IN,
            [WSTETH_AMOUNT_IN, 0].toMemoryArray(),
            IVault.RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
            bytes("")
        );
    }

    function testRemoveLiquidityCustomWithRate() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        rateProvider.mockRate(MOCK_RATE);

        vm.startPrank(alice);

        router.addLiquidity(
            address(pool),
            [address(WSTETH), address(DAI)].toMemoryArray().asAsset(),
            [WSTETH_AMOUNT_IN, DAI_AMOUNT_IN].toMemoryArray(),
            WSTETH_AMOUNT_IN,
            IVault.AddLiquidityKind.UNBALANCED,
            bytes("")
        );

        uint256 rateAdjustedAmountOut = FixedPoint.mulDown(WSTETH_AMOUNT_IN, MOCK_RATE);

        PoolData memory startingBalances = vault.getPoolData(address(pool), Rounding.ROUND_DOWN);

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onRemoveLiquidityCustom.selector,
                alice,
                WSTETH_AMOUNT_IN, // maxBptAmountIn
                [rateAdjustedAmountOut, DAI_AMOUNT_IN].toMemoryArray(), // minAmountsOut
                [startingBalances.balancesLiveScaled18[0], startingBalances.balancesLiveScaled18[1]].toMemoryArray(),
                bytes("")
            )
        );

        router.removeLiquidity(
            address(pool),
            [address(WSTETH), address(DAI)].toMemoryArray().asAsset(),
            WSTETH_AMOUNT_IN,
            [WSTETH_AMOUNT_IN, DAI_AMOUNT_IN].toMemoryArray(),
            IVault.RemoveLiquidityKind.CUSTOM,
            bytes("")
        );
    }

    function _mockInitialize(address initializer) internal {
        vm.prank(initializer);

        // The mock pool can be initialized with no liquidity; it mints some BPT to the initializer
        // to comply with the vault's required minimum.
        router.initialize(
            address(pool),
            [address(WSTETH), address(DAI)].toMemoryArray().asAsset(),
            [WSTETH_AMOUNT_IN, DAI_AMOUNT_IN].toMemoryArray(),
            0,
            bytes("")
        );
    }
}
