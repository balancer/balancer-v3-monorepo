// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
import { PoolConfigBits, PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

contract WeightedPoolTest is Test {
    using ArrayHelpers for *;

    VaultMock vault;
    BasicAuthorizerMock authorizer;
    WeightedPoolFactory factory;
    Router router;
    WeightedPool pool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant USDC_AMOUNT = 1e3 * 1e6;
    uint256 constant DAI_AMOUNT = 1e3 * 1e18;

    uint256 constant DAI_AMOUNT_IN = 1 * 1e18;
    uint256 constant USDC_AMOUNT_OUT = 1 * 1e6;

    uint256 constant DELTA = 1e9;

    bytes32 constant ZERO_BYTES32 = 0x0000000000000000000000000000000000000000000000000000000000000000;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        factory = new WeightedPoolFactory(vault, 365 days);

        router = new Router(IVault(vault), new WETHTestToken());
        USDC = new ERC20TestToken("USDC", "USDC", 6);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        IERC20[] memory tokens = [address(DAI), address(USDC)].toMemoryArray().asIERC20();
        IRateProvider[] memory rateProviders = new IRateProvider[](2);

        pool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                tokens,
                rateProviders,
                [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                ZERO_BYTES32
            )
        );

        USDC.mint(alice, USDC_AMOUNT);
        DAI.mint(alice, DAI_AMOUNT);

        USDC.mint(bob, USDC_AMOUNT);
        DAI.mint(bob, DAI_AMOUNT);

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

    function testPoolPausedState() public {
        (bool paused, uint256 pauseWindow, uint256 bufferPeriod, address pauseManager) = vault.getPoolPausedState(
            address(pool)
        );

        assertFalse(paused);
        assertApproxEqAbs(pauseWindow, 365 days, 1);
        assertApproxEqAbs(bufferPeriod, 365 days + 90 days, 1);
        assertEq(pauseManager, address(0));
    }

    function testInitialize() public {
        vm.prank(alice);

        uint256[] memory amountsIn = [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray();
        uint256 bptAmountOut = router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            amountsIn,
            // Initial BPT is invariant * tokens.length
            // Account for the precision less
            DAI_AMOUNT * 2 - DELTA,
            false,
            bytes("")
        );

        // Tokens are transferred from Alice
        assertEq(USDC.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(alice), 0);

        // Tokens are stored in the Vault
        assertEq(USDC.balanceOf(address(vault)), USDC_AMOUNT);
        assertEq(DAI.balanceOf(address(vault)), DAI_AMOUNT);

        // Tokens are deposited to the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], DAI_AMOUNT);
        assertEq(balances[1], USDC_AMOUNT);

        // amountsIn should be correct
        assertEq(amountsIn[0], DAI_AMOUNT);
        assertEq(amountsIn[1], USDC_AMOUNT);

        // should mint correct amount of BPT tokens
        // Account for the precision less
        assertApproxEqAbs(pool.balanceOf(alice), bptAmountOut, DELTA);
        assertApproxEqAbs(bptAmountOut, DAI_AMOUNT * 2, DELTA);
    }

    function testAddLiquidity() public {
        vm.prank(alice);

        // init
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray(),
            // Initial BPT is invariant * tokens.length
            // Account for the precision less
            DAI_AMOUNT * 2 - DELTA,
            false,
            bytes("")
        );

        uint256[] memory amountsIn = [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray();
        vm.prank(bob);
        uint256 bptAmountOut = router.addLiquidityUnbalanced(address(pool), amountsIn, DAI_AMOUNT, false, bytes(""));

        // Tokens are transferred from Bob
        assertEq(USDC.balanceOf(bob), 0);
        assertEq(DAI.balanceOf(bob), 0);

        // Tokens are stored in the Vault
        assertEq(USDC.balanceOf(address(vault)), USDC_AMOUNT * 2);
        assertEq(DAI.balanceOf(address(vault)), DAI_AMOUNT * 2);

        // Tokens are deposited to the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], DAI_AMOUNT * 2);
        assertEq(balances[1], USDC_AMOUNT * 2);

        // amountsIn should be correct
        assertEq(amountsIn[0], DAI_AMOUNT);
        assertEq(amountsIn[1], USDC_AMOUNT);

        // should mint correct amount of BPT tokens
        assertApproxEqAbs(pool.balanceOf(bob), bptAmountOut, DELTA);
        assertApproxEqAbs(bptAmountOut, DAI_AMOUNT * 2, DELTA);
    }

    function testRemoveLiquidity() public {
        vm.prank(alice);
        // init
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray(),
            // Initial BPT is invariant * tokens.length
            // Account for the precision less
            DAI_AMOUNT * 2 - DELTA,
            false,
            bytes("")
        );

        vm.startPrank(bob);
        router.addLiquidityUnbalanced(
            address(pool),
            [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray(),
            DAI_AMOUNT,
            false,
            bytes("")
        );

        pool.approve(address(vault), type(uint256).max);

        uint256 bobBptBalance = pool.balanceOf(bob);
        uint256 bptAmountIn = bobBptBalance;

        uint256[] memory amountsOut = router.removeLiquidityProportional(
            address(pool),
            bptAmountIn,
            [uint256(less(DAI_AMOUNT, 1e4)), uint256(less(USDC_AMOUNT, 1e4))].toMemoryArray(),
            false,
            bytes("")
        );

        vm.stopPrank();

        // Tokens are transferred to Bob
        assertApproxEqAbs(USDC.balanceOf(bob), USDC_AMOUNT, DELTA);
        assertApproxEqAbs(DAI.balanceOf(bob), DAI_AMOUNT, DELTA);

        // Tokens are stored in the Vault
        assertApproxEqAbs(USDC.balanceOf(address(vault)), USDC_AMOUNT, DELTA);
        assertApproxEqAbs(DAI.balanceOf(address(vault)), DAI_AMOUNT, DELTA);

        // Tokens are deposited to the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertApproxEqAbs(balances[0], DAI_AMOUNT, DELTA);
        assertApproxEqAbs(balances[1], USDC_AMOUNT, DELTA);

        // amountsOut are correct
        assertApproxEqAbs(amountsOut[0], DAI_AMOUNT, DELTA);
        assertApproxEqAbs(amountsOut[1], USDC_AMOUNT, DELTA);

        // should mint correct amount of BPT tokens
        assertEq(pool.balanceOf(bob), 0);
        assertEq(bobBptBalance, bptAmountIn);
    }

    function testSwap() public {
        vm.prank(alice);
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray(),
            // Initial BPT is invariant * tokens.length
            // Account for the precision less
            DAI_AMOUNT * 2 - DELTA,
            false,
            bytes("")
        );

        vm.prank(bob);
        uint256 amountCalculated = router.swapExactIn(
            address(pool),
            DAI,
            USDC,
            DAI_AMOUNT_IN,
            less(USDC_AMOUNT_OUT, 1e3),
            type(uint256).max,
            false,
            bytes("")
        );

        // Tokens are transferred from Bob
        assertEq(USDC.balanceOf(bob), USDC_AMOUNT + amountCalculated);
        assertEq(DAI.balanceOf(bob), DAI_AMOUNT - DAI_AMOUNT_IN);

        // Tokens are stored in the Vault
        assertEq(USDC.balanceOf(address(vault)), USDC_AMOUNT - amountCalculated);
        assertEq(DAI.balanceOf(address(vault)), DAI_AMOUNT + DAI_AMOUNT_IN);

        // Tokens are deposited to the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], DAI_AMOUNT + DAI_AMOUNT_IN);
        assertEq(balances[1], USDC_AMOUNT - amountCalculated);
    }

    function less(uint256 amount, uint256 base) internal pure returns (uint256) {
        return (amount * (base - 1)) / base;
    }

    function testAddLiquidityUnbalanced() public {
        vm.prank(alice);

        // init
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray(),
            // Initial BPT is invariant * tokens.length
            // Account for the precision less
            DAI_AMOUNT * 2 - DELTA,
            false,
            bytes("")
        );

        authorizer.grantRole(vault.getActionId(IVault.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setStaticSwapFeePercentage(address(pool), 10e16);

        uint256[] memory amountsIn = [uint256(1e2 * 1e18), uint256(USDC_AMOUNT)].toMemoryArray();
        vm.prank(bob);

        router.addLiquidityUnbalanced(address(pool), amountsIn, 0, false, bytes(""));
    }
}
