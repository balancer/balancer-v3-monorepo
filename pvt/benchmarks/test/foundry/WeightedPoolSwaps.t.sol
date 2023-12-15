// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";

contract WeightedPoolSwaps is Test {
    using ArrayHelpers for *;

    Vault vault;
    Router router;
    BasicAuthorizerMock authorizer;
    IRateProvider[] rateProviders;
    WeightedPool weightedPool;
    WeightedPool weightedPoolWithRate;
    ERC20TestToken WSTETH;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant MIN_SWAP_AMOUNT = 1e18;
    uint256 constant MAX_SWAP_AMOUNT = 1e3 * 1e18;
    uint256 constant INITIALIZE_AMOUNT = MAX_SWAP_AMOUNT * 100_000;
    uint256 constant INITIAL_FUNDS = INITIALIZE_AMOUNT * 100e6;
    uint256 constant MOCK_RATE = 2e18;
    uint256 constant SWAP_TIMES = 5000;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new Vault(authorizer, 30 days, 90 days);
        WeightedPoolFactory factory = new WeightedPoolFactory(vault, 365 days);
        router = new Router(IVault(vault), new WETHTestToken());
        WSTETH = new ERC20TestToken("WSTETH", "WSTETH", 18);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        rateProviders.push(new RateProviderMock());
        rateProviders.push(new RateProviderMock());

        weightedPoolWithRate = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                [address(WSTETH), address(DAI)].toMemoryArray().asIERC20(),
                rateProviders,
                [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                bytes32(0)
            )
        );

        weightedPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                [address(WSTETH), address(DAI)].toMemoryArray().asIERC20(),
                new IRateProvider[](2),
                [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                bytes32(uint256(1))
            )
        );

        WSTETH.mint(bob, INITIAL_FUNDS);
        DAI.mint(bob, INITIAL_FUNDS);

        WSTETH.mint(alice, INITIAL_FUNDS);
        DAI.mint(alice, INITIAL_FUNDS);

        vm.startPrank(bob);

        WSTETH.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.startPrank(alice);

        WSTETH.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        // Set protocol fee
        authorizer.grantRole(vault.getActionId(IVault.setProtocolSwapFeePercentage.selector), alice);
        vault.setProtocolSwapFeePercentage(50e16); // 50%

        vm.stopPrank();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(address(WSTETH), "WSTETH");
        vm.label(address(DAI), "DAI");
    }

    function testSwapGivenInWithoutRate() public {
        _initializePool(address(weightedPool));

        _testSwapGivenIn(address(weightedPool));
    }

    function testSwapGivenOutWithoutRate() public {
        _initializePool(address(weightedPool));

        _testSwapGivenOut(address(weightedPool));
    }

    function testSwapGivenInWithRate() public {
        _initializePool(address(weightedPoolWithRate));

        _testSwapGivenIn(address(weightedPoolWithRate));
    }

    function testSwapGivenOutWithRate() public {
        _initializePool(address(weightedPoolWithRate));

        _testSwapGivenOut(address(weightedPoolWithRate));
    }

    function _initializePool(address pool) internal {
        vm.startPrank(alice);

        router.initialize(
            pool,
            [address(WSTETH), address(DAI)].toMemoryArray().asIERC20(),
            [INITIALIZE_AMOUNT, INITIALIZE_AMOUNT].toMemoryArray(),
            0,
            false,
            bytes("")
        );

        // Set pool swap fee
        authorizer.grantRole(vault.getActionId(IVault.setStaticSwapFeePercentage.selector), alice);
        vault.setStaticSwapFeePercentage(pool, 1e16); // 1%

        vm.stopPrank();
    }

    function _testSwapGivenIn(address pool) internal {
        uint256 amountIn = MAX_SWAP_AMOUNT;

        vm.startPrank(bob);
        for (uint256 i = 0; i < SWAP_TIMES; ++i) {
            uint256 amountOut = router.swapExactIn(
                pool,
                DAI,
                WSTETH,
                amountIn,
                0,
                type(uint256).max,
                false,
                bytes("")
            );

            router.swapExactIn(
                pool,
                WSTETH,
                DAI,
                amountOut,
                0,
                type(uint256).max,
                false,
                bytes("")
            );
        }
        vm.stopPrank();
    }

    function _testSwapGivenOut(address pool) internal {
        uint256 amountOut = MAX_SWAP_AMOUNT;

        vm.startPrank(bob);
        for (uint256 i = 0; i < SWAP_TIMES; ++i) {
            uint256 amountIn = router.swapExactOut(
                pool,
                DAI,
                WSTETH,
                amountOut,
                type(uint256).max,
                type(uint256).max,
                false,
                bytes("")
            );

            router.swapExactOut(
                pool,
                WSTETH,
                DAI,
                amountIn,
                type(uint256).max,
                type(uint256).max,
                false,
                bytes("")
            );
        }
        vm.stopPrank();
    }
}
