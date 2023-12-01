// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { ERC20PoolMock } from "../../contracts/test/ERC20PoolMock.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

contract VaultSwapWithRatesTest is Test {
    using AssetHelpers for *;
    using ArrayHelpers for *;

    VaultMock vault;
    Router router;
    BasicAuthorizerMock authorizer;
    RateProviderMock rateProvider;
    ERC20PoolMock pool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);
    address admin = vm.addr(3);

    uint256 constant AMOUNT = 1e3 * 1e18;
    uint256 constant SWAP_FEE = 1e3 * 1e16; // 1%
    uint256 constant PROTOCOL_SWAP_FEE = SWAP_FEE / 2;

    uint256 constant MOCK_RATE = 2e18;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), address(0));
        USDC = new ERC20TestToken("USDC", "USDC", 18);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProvider = new RateProviderMock();
        rateProviders[0] = rateProvider;

        pool = new ERC20PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );

        USDC.mint(bob, AMOUNT);
        DAI.mint(bob, AMOUNT);

        USDC.mint(alice, AMOUNT);
        DAI.mint(alice, AMOUNT);

        vm.startPrank(bob);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.startPrank(alice);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(admin, "admin");
        vm.label(address(USDC), "USDC");
        vm.label(address(DAI), "DAI");
    }

    function initPool() public {
        vm.prank(alice);
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(AMOUNT), uint256(AMOUNT)].toMemoryArray(),
            0,
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
        (, , , IRateProvider[] memory rateProviders) = vault.getPoolTokenInfo(address(pool));

        assertEq(address(rateProviders[0]), address(rateProvider));
        assertEq(address(rateProviders[1]), address(0));
    }

    function testSwapGivenInWithRate() public {
        rateProvider.mockRate(MOCK_RATE);

        initPool();

        uint256 rateAdjustedAmount = FixedPoint.divDown(AMOUNT, MOCK_RATE);

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            AMOUNT,
            rateAdjustedAmount, // Adjust limit
            type(uint256).max,
            bytes("")
        );

        // assets are transferred to/from Bob
        assertEq(USDC.balanceOf(bob), 0);
        assertEq(DAI.balanceOf(bob), AMOUNT + rateAdjustedAmount);

        // assets are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], AMOUNT - rateAdjustedAmount);
        assertEq(balances[1], AMOUNT * 2);

        assertEq(DAI.balanceOf(address(vault)), AMOUNT - rateAdjustedAmount);
        assertEq(USDC.balanceOf(address(vault)), AMOUNT * 2);
    }

    function testSwapGivenOutWithRate() public {
        rateProvider.mockRate(MOCK_RATE);

        initPool();

        uint256 rateAdjustedAmount = FixedPoint.divDown(AMOUNT, MOCK_RATE);

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_OUT,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            rateAdjustedAmount,
            AMOUNT,
            type(uint256).max,
            bytes("")
        );

        // asssets are transferred to/from Bob
        assertEq(USDC.balanceOf(bob), 0);
        assertEq(DAI.balanceOf(bob), AMOUNT + rateAdjustedAmount);

        // assets are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], AMOUNT - rateAdjustedAmount);
        assertEq(balances[1], AMOUNT * 2);

        // vault are adjusted balances
        assertEq(DAI.balanceOf(address(vault)), AMOUNT - rateAdjustedAmount);
        assertEq(USDC.balanceOf(address(vault)), 2 * AMOUNT);
    }
}
