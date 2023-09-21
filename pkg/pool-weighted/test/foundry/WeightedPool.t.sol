// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IERC20Errors } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/token/IERC20Errors.sol";
import { AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
import { PoolConfigBits, PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";

contract WeightedPoolTest is Test {
    using AssetHelpers for address[];
    using AssetHelpers for address[];
    using ArrayHelpers for address[2];
    using ArrayHelpers for uint256[2];

    VaultMock vault;
    Router router;
    WeightedPool pool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant USDC_AMOUNT_IN = 1e3 * 1e6;
    uint256 constant DAI_AMOUNT_IN = 1e3 * 1e18;
    uint256 constant DELTA = 1e9;

    function setUp() public {
        vault = new VaultMock(30 days, 90 days);
        router = new Router(IVault(vault), address(0));
        USDC = new ERC20TestToken("USDC", "USDC", 6);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        IERC20[] memory tokens = [address(DAI), address(USDC)].toMemoryArray().asIERC20();
        pool = new WeightedPool(
            WeightedPool.NewPoolParams({
                name: "ERC20 Pool",
                symbol: "ERC20POOL",
                tokens: tokens,
                normalizedWeights: [uint256(0.50e18), uint256(0.50e18)].toMemoryArray()
            }),
            vault,
            30 days,
            90 days
        );

        vault.registerPool(address(pool), address(0), tokens, PoolConfigBits.wrap(0).toPoolConfig());

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
        vm.label(address(vault), "Vault");
        vm.label(address(router), "Router");
        vm.label(address(pool), "Pool");
    }

    function testInitialize() public {
        vm.prank(alice);
        (uint256[] memory amountsIn, uint256 bptAmountOut) = router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            // Initial BTP is invariant * tokens.length
            // Account for the precision less
            DAI_AMOUNT_IN * 2 - DELTA,
            bytes("")
        );

        // asssets are transferred from Alice
        assertEq(USDC.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(alice), 0);

        // assets are stored in the Vault
        assertEq(USDC.balanceOf(address(vault)), USDC_AMOUNT_IN);
        assertEq(DAI.balanceOf(address(vault)), DAI_AMOUNT_IN);

        // assets are deposited to the pool
        (, uint256[] memory balances) = vault.getPoolTokens(address(pool));
        assertEq(balances[0], DAI_AMOUNT_IN);
        assertEq(balances[1], USDC_AMOUNT_IN);

        // amountsIn should be correct
        assertEq(amountsIn[0], DAI_AMOUNT_IN);
        assertEq(amountsIn[1], USDC_AMOUNT_IN);

        // should mint correct amount of BPT tokens
        // Account for the precision less
        assertApproxEqAbs(pool.balanceOf(alice), bptAmountOut , DELTA);
        assertApproxEqAbs(bptAmountOut, DAI_AMOUNT_IN * 2 , DELTA);
    }

    function testAddLiquidity() public {
        vm.prank(alice);
        // init
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            // Initial BTP is invariant * tokens.length
            // Account for the precision less
            DAI_AMOUNT_IN * 2 - DELTA,
            bytes("")
        );

        vm.prank(bob);
        (uint256[] memory amountsIn, uint256 bptAmountOut) = router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            IBasePool.AddLiquidityKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            bytes("")
        );

        // asssets are transferred from Bob
        assertEq(USDC.balanceOf(bob), 0);
        assertEq(DAI.balanceOf(bob), 0);

        // assets are stored in the Vault
        assertEq(USDC.balanceOf(address(vault)), USDC_AMOUNT_IN * 2);
        assertEq(DAI.balanceOf(address(vault)), DAI_AMOUNT_IN * 2);

        // assets are deposited to the pool
        (, uint256[] memory balances) = vault.getPoolTokens(address(pool));
        assertEq(balances[0], DAI_AMOUNT_IN * 2);
        assertEq(balances[1], USDC_AMOUNT_IN * 2);

        // amountsIn should be correct
        assertEq(amountsIn[0], DAI_AMOUNT_IN);
        assertEq(amountsIn[1], USDC_AMOUNT_IN);

        // should mint correct amount of BPT tokens
        assertApproxEqAbs(pool.balanceOf(bob), bptAmountOut , DELTA);
        assertApproxEqAbs(bptAmountOut, DAI_AMOUNT_IN * 2 , DELTA);
    }

    function testRemoveLiquidity() public {
        vm.prank(alice);
        // init
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            // Initial BTP is invariant * tokens.length
            // Account for the precision less
            DAI_AMOUNT_IN * 2 - DELTA,
            bytes("")
        );

        vm.startPrank(bob);
        router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            IBasePool.AddLiquidityKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            bytes("")
        );

        pool.approve(address(vault), type(uint256).max);

        uint256 bobBtpBalance = pool.balanceOf(bob);

        (uint256[] memory amountsOut, uint256 bptAmountIn) = router.removeLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(less(DAI_AMOUNT_IN)), uint256(less(USDC_AMOUNT_IN))].toMemoryArray(),
            bobBtpBalance,
            IBasePool.RemoveLiquidityKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
            bytes("")
        );

        vm.stopPrank();

        // asssets are transferred to Bob
        assertApproxEqAbs(USDC.balanceOf(bob), USDC_AMOUNT_IN, DELTA);
        assertApproxEqAbs(DAI.balanceOf(bob), DAI_AMOUNT_IN, DELTA);

        // assets are stored in the Vault
        assertApproxEqAbs(USDC.balanceOf(address(vault)), USDC_AMOUNT_IN, DELTA);
        assertApproxEqAbs(DAI.balanceOf(address(vault)), DAI_AMOUNT_IN, DELTA);

        // assets are deposited to the pool
        (, uint256[] memory balances) = vault.getPoolTokens(address(pool));
        assertApproxEqAbs(balances[0], DAI_AMOUNT_IN, DELTA);
        assertApproxEqAbs(balances[1], USDC_AMOUNT_IN, DELTA);

        // amountsOut are correct
        assertApproxEqAbs(amountsOut[0], DAI_AMOUNT_IN, DELTA);
        assertApproxEqAbs(amountsOut[1], USDC_AMOUNT_IN, DELTA);

        // should mint correct amount of BPT tokens
        assertEq(pool.balanceOf(bob), 0);
        assertEq(bobBtpBalance, bptAmountIn);
    }


    function less(uint256 amount) pure internal returns (uint256) {
        return amount * 9999/10000;
    }
}
