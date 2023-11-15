// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IERC20Errors } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/token/IERC20Errors.sol";
import { AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";

import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { ERC20PoolMock } from "../../contracts/test/ERC20PoolMock.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

contract VaultSwapTest is Test {
    using AssetHelpers for *;
    using ArrayHelpers for *;

    VaultMock vault;
    Router router;
    BasicAuthorizerMock authorizer;
    ERC20PoolMock pool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant AMOUNT = 1e3 * 1e18;
    uint256 constant SWAP_FEE = (AMOUNT * 1e4) / 1e6;
    uint256 constant PROTOCOL_SWAP_FEE = SWAP_FEE / 2;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), address(0));
        USDC = new ERC20TestToken("USDC", "USDC", 18);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        pool = new ERC20PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            address(0),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            true
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
        vault.setStaticSwapFeePercentage(address(pool), 1e4);
    }

    function setProtocolSwapFeePercentage() internal {
        authorizer.grantRole(vault.getActionId(IVault.setProtocolSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setProtocolSwapFeePercentage(50e4); // %50
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

    function testSwapGivenIn() public {
        initPool();

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

        // assets are transferred to/from Bob
        assertEq(USDC.balanceOf(bob), 0);
        assertEq(DAI.balanceOf(bob), 2 * AMOUNT);

        // assets are adjusted in the pool
        (, uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], 0);
        assertEq(balances[1], AMOUNT * 2);
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
        (, uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], 0);
        assertEq(balances[1], AMOUNT * 2);
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
        (, uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], SWAP_FEE);
        assertEq(balances[1], 2 * AMOUNT);
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

        // asssets are transferred to/from Bob
        assertEq(USDC.balanceOf(bob), bobUsdcBeforeSwap - AMOUNT);
        assertEq(DAI.balanceOf(bob), bobDaiBeforeSwap + AMOUNT - SWAP_FEE);

        // assets are adjusted in the pool
        (, uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], SWAP_FEE - PROTOCOL_SWAP_FEE);
        assertEq(balances[1], 2 * AMOUNT);

        // protocol fees are accrued
        assertEq(PROTOCOL_SWAP_FEE, vault.getProtocolSwapFee(address(DAI)));
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
        (, uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], SWAP_FEE);
        assertEq(balances[1], 2 * AMOUNT);
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
        (, uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], SWAP_FEE - PROTOCOL_SWAP_FEE);
        assertEq(balances[1], 2 * AMOUNT);

        // protocol fees are accrued
        assertEq(PROTOCOL_SWAP_FEE, vault.getProtocolSwapFee(address(DAI)));
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
        (, uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], SWAP_FEE - PROTOCOL_SWAP_FEE);
        assertEq(balances[1], 2 * AMOUNT);

        // protocol fees are accrued
        assertEq(PROTOCOL_SWAP_FEE, vault.getProtocolSwapFee(address(DAI)));
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

        uint256 aliceBalanceBefore = USDC.balanceOf(alice);

        authorizer.grantRole(vault.getActionId(IVault.collectProtocolFees.selector), alice);
        vm.prank(alice);
        vault.collectProtocolFees([address(DAI)].toMemoryArray().asIERC20());

        // protocol fees are zero
        assertEq(0, vault.getProtocolSwapFee(address(DAI)));

        // alice received protocol fees
        assertEq(DAI.balanceOf(alice), aliceBalanceBefore + (PROTOCOL_SWAP_FEE));
    }
}
