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

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { ERC20PoolMock } from "../../contracts/test/ERC20PoolMock.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

contract VaultSwapTest is Test {
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

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), address(0));
        USDC = new ERC20TestToken("USDC", "USDC", 18);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProvider = new RateProviderMock();
        rateProvider.setUnderlyingToken(DAI);
        rateProvider.setYieldExemptFlag(true);

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

    function testInitialRateProviderState() public {
        (, , , IRateProvider[] memory rateProviders) = vault.getPoolTokenInfo(address(pool));

        assertEq(address(rateProviders[0]), address(rateProvider));
        assertEq(address(rateProviders[1]), address(0));
        assertEq(address(rateProviders[0].getUnderlyingToken()), address(DAI));
        assertTrue(rateProviders[0].isExemptFromYieldProtocolFee());
    }

    function testCannotSwapWhenPaused() public {
        vm.prank(alice);
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(AMOUNT), uint256(AMOUNT)].toMemoryArray(),
            0,
            bytes("")
        );

        vault.manualPausePool(address(pool));

        vm.expectRevert(abi.encodeWithSelector(IVault.PoolPaused.selector, address(pool)));

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            AMOUNT,
            AMOUNT,
            type(uint256).max,
            bytes("")
        );
    }

    function testSwapNotInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(IVault.PoolNotInitialized.selector, address(pool)));
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            AMOUNT,
            AMOUNT,
            type(uint256).max,
            bytes("")
        );
    }

    function testSwapGivenIn(uint64 rate) public {
        vm.assume(rate >= 1e18);
        vm.assume(rate <= 10e18);

        initPool();

        rateProvider.mockRate(rate);

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            AMOUNT,
            (AMOUNT * 1e18) / rate,
            type(uint256).max,
            bytes("")
        );

        uint256 rateAdjustedBobBalance = AMOUNT + ((AMOUNT * 1e18) / rate);
        uint256 rateAdjustedPoolBalance = AMOUNT - ((AMOUNT * 1e18) / rate);

        // assets are transferred to/from Bob
        assertEq(USDC.balanceOf(bob), 0);
        assertEq(DAI.balanceOf(bob), rateAdjustedBobBalance);

        // assets are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], rateAdjustedPoolBalance);
        assertEq(balances[1], AMOUNT * 2);

        // vault are adjusted balances
        assertEq(DAI.balanceOf(address(vault)), rateAdjustedPoolBalance);
        assertEq(USDC.balanceOf(address(vault)), AMOUNT * 2);
    }

    function testSwapGivenOut() public {
        initPool();

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_OUT,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            AMOUNT,
            AMOUNT,
            type(uint256).max,
            bytes("")
        );

        // asssets are transferred to/from Bob
        assertEq(USDC.balanceOf(bob), 0);
        assertEq(DAI.balanceOf(bob), 2 * AMOUNT);

        // assets are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], 0);
        assertEq(balances[1], AMOUNT * 2);

        // vault are adjusted balances
        assertEq(DAI.balanceOf(address(vault)), 0);
        assertEq(USDC.balanceOf(address(vault)), 2 * AMOUNT);
    }

    function testSwapFeeGivenIn() public {
        USDC.mint(bob, AMOUNT);

        initPool();
        setSwapFeePercentage();

        uint256 bobUsdcBeforeSwap = USDC.balanceOf(bob);
        uint256 bobDaiBeforeSwap = DAI.balanceOf(bob);

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            AMOUNT,
            AMOUNT - SWAP_FEE,
            type(uint256).max,
            bytes("")
        );

        // asssets are transferred to/from Bob
        assertEq(USDC.balanceOf(bob), bobUsdcBeforeSwap - AMOUNT);
        assertEq(DAI.balanceOf(bob), bobDaiBeforeSwap + AMOUNT - SWAP_FEE);

        // assets are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], SWAP_FEE);
        assertEq(balances[1], 2 * AMOUNT);

        // vault are adjusted balances
        assertEq(DAI.balanceOf(address(vault)), SWAP_FEE);
        assertEq(USDC.balanceOf(address(vault)), 2 * AMOUNT);
    }

    function testProtocolSwapFeeGivenIn() public {
        USDC.mint(bob, AMOUNT);

        initPool();
        setSwapFeePercentage();
        setProtocolSwapFeePercentage();

        uint256 bobUsdcBeforeSwap = USDC.balanceOf(bob);
        uint256 bobDaiBeforeSwap = DAI.balanceOf(bob);

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            AMOUNT,
            AMOUNT - SWAP_FEE,
            type(uint256).max,
            bytes("")
        );

        // asssets are transferred to/from Bob: USDC in, DAI out
        assertEq(DAI.balanceOf(bob), bobDaiBeforeSwap + AMOUNT - SWAP_FEE);
        assertEq(USDC.balanceOf(bob), bobUsdcBeforeSwap - AMOUNT);

        // assets are adjusted in the pool: DAI out, USDC in
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], SWAP_FEE - PROTOCOL_SWAP_FEE);
        assertEq(balances[1], 2 * AMOUNT);

        // protocol fees are accrued
        assertEq(PROTOCOL_SWAP_FEE, vault.getProtocolSwapFee(address(DAI)));

        // vault are adjusted balances
        assertEq(DAI.balanceOf(address(vault)), SWAP_FEE);
        assertEq(USDC.balanceOf(address(vault)), 2 * AMOUNT);
    }

    function testSwapFeeGivenOut() public {
        USDC.mint(bob, AMOUNT);

        initPool();
        setSwapFeePercentage();

        uint256 bobUsdcBeforeSwap = USDC.balanceOf(bob);
        uint256 bobDaiBeforeSwap = DAI.balanceOf(bob);

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_OUT,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            AMOUNT - SWAP_FEE,
            AMOUNT,
            type(uint256).max,
            bytes("")
        );

        // asssets are transferred to/from Bob
        assertEq(USDC.balanceOf(bob), bobUsdcBeforeSwap - AMOUNT);
        assertEq(DAI.balanceOf(bob), bobDaiBeforeSwap + AMOUNT - SWAP_FEE);

        // assets are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], SWAP_FEE);
        assertEq(balances[1], 2 * AMOUNT);

        // vault are adjusted balances
        assertEq(DAI.balanceOf(address(vault)), SWAP_FEE);
        assertEq(USDC.balanceOf(address(vault)), 2 * AMOUNT);
    }

    function testProtocolSwapFeeGivenOut() public {
        USDC.mint(bob, AMOUNT);

        initPool();
        setSwapFeePercentage();
        setProtocolSwapFeePercentage();

        uint256 bobUsdcBeforeSwap = USDC.balanceOf(bob);
        uint256 bobDaiBeforeSwap = DAI.balanceOf(bob);

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_OUT,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            AMOUNT - SWAP_FEE,
            AMOUNT,
            type(uint256).max,
            bytes("")
        );

        // asssets are transferred to/from Bob
        assertEq(USDC.balanceOf(bob), bobUsdcBeforeSwap - AMOUNT);
        assertEq(DAI.balanceOf(bob), bobDaiBeforeSwap + AMOUNT - SWAP_FEE);

        // assets are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], SWAP_FEE - PROTOCOL_SWAP_FEE);
        assertEq(balances[1], 2 * AMOUNT);

        // protocol fees are accrued
        assertEq(PROTOCOL_SWAP_FEE, vault.getProtocolSwapFee(address(DAI)));

        // vault are adjusted balances
        assertEq(DAI.balanceOf(address(vault)), SWAP_FEE);
        assertEq(USDC.balanceOf(address(vault)), 2 * AMOUNT);
    }

    function testProtocolSwapFeeAccumulation() public {
        USDC.mint(bob, AMOUNT);

        initPool();
        setSwapFeePercentage();
        setProtocolSwapFeePercentage();

        uint256 bobUsdcBeforeSwap = USDC.balanceOf(bob);
        uint256 bobDaiBeforeSwap = DAI.balanceOf(bob);

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            AMOUNT / 2,
            AMOUNT / 2 - SWAP_FEE / 2,
            type(uint256).max,
            bytes("")
        );

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            AMOUNT / 2,
            AMOUNT / 2 - SWAP_FEE / 2,
            type(uint256).max,
            bytes("")
        );

        // asssets are transferred to/from Bob
        assertEq(USDC.balanceOf(bob), bobUsdcBeforeSwap - AMOUNT);
        assertEq(DAI.balanceOf(bob), bobDaiBeforeSwap + AMOUNT - SWAP_FEE);

        // assets are adjusted in the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], SWAP_FEE - PROTOCOL_SWAP_FEE);
        assertEq(balances[1], 2 * AMOUNT);

        // protocol fees are accrued
        assertEq(PROTOCOL_SWAP_FEE, vault.getProtocolSwapFee(address(DAI)));

        // vault are adjusted balances
        assertEq(DAI.balanceOf(address(vault)), SWAP_FEE);
        assertEq(USDC.balanceOf(address(vault)), 2 * AMOUNT);
    }

    function testCollectProtocolFees() public {
        USDC.mint(bob, AMOUNT);

        initPool();
        setSwapFeePercentage();
        setProtocolSwapFeePercentage();

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            AMOUNT,
            AMOUNT - SWAP_FEE,
            type(uint256).max,
            bytes("")
        );

        authorizer.grantRole(vault.getActionId(IVault.collectProtocolFees.selector), admin);
        vm.prank(admin);
        vault.collectProtocolFees([address(DAI)].toMemoryArray().asIERC20());

        // protocol fees are zero
        assertEq(0, vault.getProtocolSwapFee(address(DAI)));

        // alice received protocol fees
        assertEq(DAI.balanceOf(admin), (PROTOCOL_SWAP_FEE));
    }
}
