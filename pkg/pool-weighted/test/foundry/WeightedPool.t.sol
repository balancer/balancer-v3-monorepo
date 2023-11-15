// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IERC20Errors } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/token/IERC20Errors.sol";
import { AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
import { PoolConfigBits, PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";

contract WeightedPoolTest is Test {
    using AssetHelpers for *;
    using ArrayHelpers for address[2];
    using ArrayHelpers for uint256[2];

    VaultMock vault;
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

    function setUp() public {
        BasicAuthorizerMock authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
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
            vault
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

    function testInitialize() public {
        vm.prank(alice);

        uint256[] memory amountsIn = [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray();
        uint256 bptAmountOut = router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            amountsIn,
            // Initial BPT is invariant * tokens.length
            // Account for the precision less
            DAI_AMOUNT * 2 - DELTA,
            bytes("")
        );

        // assets are transferred from Alice
        assertEq(USDC.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(alice), 0);

        // assets are stored in the Vault
        assertEq(USDC.balanceOf(address(vault)), USDC_AMOUNT);
        assertEq(DAI.balanceOf(address(vault)), DAI_AMOUNT);

        // assets are deposited to the pool
        (, uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
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
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray(),
            // Initial BPT is invariant * tokens.length
            // Account for the precision less
            DAI_AMOUNT * 2 - DELTA,
            bytes("")
        );

        vm.prank(bob);
        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray(),
            DAI_AMOUNT,
            IVault.AddLiquidityKind.UNBALANCED,
            bytes("")
        );

        // assets are transferred from Bob
        assertEq(USDC.balanceOf(bob), 0);
        assertEq(DAI.balanceOf(bob), 0);

        // assets are stored in the Vault
        assertEq(USDC.balanceOf(address(vault)), USDC_AMOUNT * 2);
        assertEq(DAI.balanceOf(address(vault)), DAI_AMOUNT * 2);

        // assets are deposited to the pool
        (, uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
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
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray(),
            // Initial BPT is invariant * tokens.length
            // Account for the precision less
            DAI_AMOUNT * 2 - DELTA,
            bytes("")
        );

        vm.startPrank(bob);
        router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray(),
            DAI_AMOUNT,
            IVault.AddLiquidityKind.UNBALANCED,
            bytes("")
        );

        pool.approve(address(vault), type(uint256).max);

        uint256 bobBptBalance = pool.balanceOf(bob);

        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = router.removeLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            bobBptBalance,
            [uint256(less(DAI_AMOUNT, 1e4)), uint256(less(USDC_AMOUNT, 1e4))].toMemoryArray(),
            IVault.RemoveLiquidityKind.PROPORTIONAL,
            bytes("")
        );

        vm.stopPrank();

        // assets are transferred to Bob
        assertApproxEqAbs(USDC.balanceOf(bob), USDC_AMOUNT, DELTA);
        assertApproxEqAbs(DAI.balanceOf(bob), DAI_AMOUNT, DELTA);

        // assets are stored in the Vault
        assertApproxEqAbs(USDC.balanceOf(address(vault)), USDC_AMOUNT, DELTA);
        assertApproxEqAbs(DAI.balanceOf(address(vault)), DAI_AMOUNT, DELTA);

        // assets are deposited to the pool
        (, uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
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
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray(),
            // Initial BPT is invariant * tokens.length
            // Account for the precision less
            DAI_AMOUNT * 2 - DELTA,
            bytes("")
        );

        vm.prank(bob);
        uint256 amountCalculated = router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            DAI.asAsset(),
            USDC.asAsset(),
            DAI_AMOUNT_IN,
            less(USDC_AMOUNT_OUT, 1e3),
            type(uint256).max,
            bytes("")
        );

        // assets are transferred from Bob
        assertEq(USDC.balanceOf(bob), USDC_AMOUNT + amountCalculated);
        assertEq(DAI.balanceOf(bob), DAI_AMOUNT - DAI_AMOUNT_IN);

        // assets are stored in the Vault
        assertEq(USDC.balanceOf(address(vault)), USDC_AMOUNT - amountCalculated);
        assertEq(DAI.balanceOf(address(vault)), DAI_AMOUNT + DAI_AMOUNT_IN);

        // assets are deposited to the pool
        (, uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], DAI_AMOUNT + DAI_AMOUNT_IN);
        assertEq(balances[1], USDC_AMOUNT - amountCalculated);
    }

    function less(uint256 amount, uint256 base) internal pure returns (uint256) {
        return (amount * (base - 1)) / base;
    }
}
