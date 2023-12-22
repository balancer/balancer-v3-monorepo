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
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

contract VaultSwapWithRatesTest is Test {
    using ArrayHelpers for *;

    VaultMock vault;
    Router router;
    BasicAuthorizerMock authorizer;
    RateProviderMock rateProvider;
    PoolMock pool;
    ERC20TestToken WSTETH;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant AMOUNT = 1e3 * 1e18;
    uint256 constant MOCK_RATE = 2e18;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), new WETHTestToken());
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

        WSTETH.mint(bob, AMOUNT);
        DAI.mint(bob, AMOUNT);

        WSTETH.mint(alice, AMOUNT);
        DAI.mint(alice, AMOUNT);

        vm.startPrank(bob);

        WSTETH.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.startPrank(alice);

        WSTETH.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(address(WSTETH), "WSTETH");
        vm.label(address(DAI), "DAI");
    }

    function initPool() public {
        vm.prank(alice);
        router.initialize(
            address(pool),
            [address(WSTETH), address(DAI)].toMemoryArray().asIERC20(),
            [uint256(AMOUNT), uint256(AMOUNT)].toMemoryArray(),
            0,
            false,
            bytes("")
        );
    }

    function testInitializePoolWithRate() public {
        uint256 snapshot = vm.snapshot();

        initPool();

        uint256 aliceBpt = pool.balanceOf(alice);

        vm.revertTo(snapshot);

        // Initialize again with rate
        rateProvider.mockRate(MOCK_RATE);

        initPool();

        uint256 aliceBptWithRate = pool.balanceOf(alice);

        assertApproxEqAbs(aliceBptWithRate, FixedPoint.mulDown(aliceBpt, MOCK_RATE), 1e6);
    }

    function testInitialRateProviderState() public {
        (, , , , IRateProvider[] memory rateProviders) = vault.getPoolTokenInfo(address(pool));

        assertEq(address(rateProviders[0]), address(rateProvider));
        assertEq(address(rateProviders[1]), address(0));
    }

    function testSwapGivenInWithRate() public {
        rateProvider.mockRate(MOCK_RATE);

        initPool();

        uint256 rateAdjustedLimit = FixedPoint.divDown(AMOUNT, MOCK_RATE);
        uint256 rateAdjustedAmount = FixedPoint.mulDown(AMOUNT, MOCK_RATE);

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.SwapParams({
                    kind: IVault.SwapKind.GIVEN_IN,
                    amountGivenScaled18: AMOUNT,
                    balancesScaled18: [rateAdjustedAmount, AMOUNT].toMemoryArray(),
                    indexIn: 1,
                    indexOut: 0,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );

        vm.prank(bob);
        router.swapExactIn(
            address(pool),
            DAI,
            WSTETH,
            AMOUNT,
            rateAdjustedLimit,
            type(uint256).max,
            false,
            bytes("")
        );
    }

    function testSwapGivenOutWithRate() public {
        rateProvider.mockRate(MOCK_RATE);

        initPool();

        uint256 rateAdjustedBalance = FixedPoint.mulDown(AMOUNT, MOCK_RATE);
        uint256 rateAdjustedAmountGiven = FixedPoint.divDown(AMOUNT, MOCK_RATE);

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.SwapParams({
                    kind: IVault.SwapKind.GIVEN_OUT,
                    amountGivenScaled18: AMOUNT,
                    balancesScaled18: [rateAdjustedBalance, AMOUNT].toMemoryArray(),
                    indexIn: 1,
                    indexOut: 0,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );

        vm.prank(bob);
        router.swapExactOut(
            address(pool),
            DAI,
            WSTETH,
            rateAdjustedAmountGiven,
            AMOUNT,
            type(uint256).max,
            false,
            bytes("")
        );
    }
}
