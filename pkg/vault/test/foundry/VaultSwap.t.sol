// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IERC20Errors } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/token/IERC20Errors.sol";
import { AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";

import { PoolMock } from "@balancer-labs/v3-pool-utils/contracts/test/PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

contract VaultSwapTest is Test {
    using AssetHelpers for address;
    using AssetHelpers for address[];
    using AssetHelpers for address[];
    using ArrayHelpers for address[2];
    using ArrayHelpers for uint256[2];

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
        router = new Router(IVault(vault), address(0));
        USDC = new ERC20TestToken("USDC", "USDC", 6);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        pool = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            address(0),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            true
        );

        USDC.mint(bob, USDC_AMOUNT_IN);
        DAI.mint(bob, DAI_AMOUNT_IN);

        USDC.mint(alice, USDC_AMOUNT_IN);
        DAI.mint(alice, DAI_AMOUNT_IN);

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

        vm.prank(alice);
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(0), uint256(0)].toMemoryArray(),
            0,
            bytes("")
        );
    }

    function getSwapFee(uint256 amount, uint256 percentage) public pure returns (uint256) {
        // round up
        return (amount * 100) / (100 - percentage) + 1 - amount;
    }

    function initPool() public {
        vm.prank(alice);
        router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            IBasePool.AddLiquidityKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            bytes("")
        );

        pool.setMultiplier(1e30);
    }

    function testSwap() public {
        initPool();

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            USDC_AMOUNT_IN,
            DAI_AMOUNT_IN,
            type(uint256).max,
            bytes("")
        );

        // asssets are transferred to/from Bob
        assertEq(USDC.balanceOf(bob), 0);
        assertEq(DAI.balanceOf(bob), 2 * DAI_AMOUNT_IN);

        // assets are adjusted in the pool
        (, uint256[] memory balances) = vault.getPoolTokens(address(pool));
        assertEq(balances[0], 0);
        assertEq(balances[1], USDC_AMOUNT_IN * 2);
    }

    function testSwapFeeGivenIn() public {
        uint256 USDC_SWAP_FEE = getSwapFee(USDC_AMOUNT_IN, 1);

        USDC.mint(bob, USDC_AMOUNT_IN);

        initPool();

        authorizer.grantRole(vault.getActionId(IVault.setSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setSwapFeePercentage(address(pool), 1e4);

        uint256 bobUsdcBeforeSwap = USDC.balanceOf(bob);
        uint256 bobDaiBeforeSwap = DAI.balanceOf(bob);

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            USDC_AMOUNT_IN + USDC_SWAP_FEE,
            DAI_AMOUNT_IN,
            type(uint256).max,
            bytes("")
        );

        // asssets are transferred to/from Bob
        assertEq(USDC.balanceOf(bob), bobUsdcBeforeSwap - (USDC_AMOUNT_IN + USDC_SWAP_FEE));
        assertEq(DAI.balanceOf(bob), bobDaiBeforeSwap + DAI_AMOUNT_IN);

        // assets are adjusted in the pool
        (, uint256[] memory balances) = vault.getPoolTokens(address(pool));
        assertEq(balances[0], 0);
        assertEq(balances[1], 2 * USDC_AMOUNT_IN + USDC_SWAP_FEE);
    }

    function testProtocolSwapFeeGivenIn() public {
        uint256 USDC_SWAP_FEE = getSwapFee(USDC_AMOUNT_IN, 1);

        USDC.mint(bob, USDC_AMOUNT_IN);

        initPool();

        authorizer.grantRole(vault.getActionId(IVault.setSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setSwapFeePercentage(address(pool), 1e4); // %1

        authorizer.grantRole(vault.getActionId(IVault.setProtocolSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setProtocolSwapFeePercentage(50e4); // %50

        uint256 bobUsdcBeforeSwap = USDC.balanceOf(bob);
        uint256 bobDaiBeforeSwap = DAI.balanceOf(bob);

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            USDC_AMOUNT_IN + USDC_SWAP_FEE,
            DAI_AMOUNT_IN,
            type(uint256).max,
            bytes("")
        );

        // asssets are transferred to/from Bob
        assertEq(USDC.balanceOf(bob), bobUsdcBeforeSwap - (USDC_AMOUNT_IN + USDC_SWAP_FEE));
        assertEq(DAI.balanceOf(bob), bobDaiBeforeSwap + DAI_AMOUNT_IN);

        // assets are adjusted in the pool
        (, uint256[] memory balances) = vault.getPoolTokens(address(pool));
        assertEq(balances[0], 0);
        assertEq(balances[1], 2 * USDC_AMOUNT_IN + USDC_SWAP_FEE);
    }

    function testSwapFeeGivenOut() public {
        uint256 USDC_SWAP_FEE = getSwapFee(USDC_AMOUNT_IN, 1);
        USDC.mint(bob, USDC_AMOUNT_IN);

        initPool();

        vm.prank(alice);

        authorizer.grantRole(vault.getActionId(IVault.setSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setSwapFeePercentage(address(pool), 1e4);

        uint256 bobUsdcBeforeSwap = USDC.balanceOf(bob);
        uint256 bobDaiBeforeSwap = DAI.balanceOf(bob);

        vm.prank(bob);
        router.swap(
            IVault.SwapKind.GIVEN_OUT,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            DAI_AMOUNT_IN,
            USDC_AMOUNT_IN + USDC_SWAP_FEE,
            type(uint256).max,
            bytes("")
        );

        // asssets are transferred to/from Bob
        assertEq(USDC.balanceOf(bob), bobUsdcBeforeSwap - (USDC_AMOUNT_IN + USDC_SWAP_FEE));
        assertEq(DAI.balanceOf(bob), bobDaiBeforeSwap + DAI_AMOUNT_IN);

        // assets are adjusted in the pool
        (, uint256[] memory balances) = vault.getPoolTokens(address(pool));
        assertEq(balances[0], 0);
        assertEq(balances[1], 2 * USDC_AMOUNT_IN + USDC_SWAP_FEE);
    }
}
