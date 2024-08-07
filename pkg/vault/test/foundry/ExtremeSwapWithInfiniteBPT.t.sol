// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract ExtremeSwapWithInfiniteBPTTest is BaseVaultTest {
    using ArrayHelpers for *;
    using CastingHelpers for *;

    uint256 internal poolInitialAmount = 1e18;
    PoolMock internal poolA;
    PoolMock internal poolB;

    uint256 poolAIdx = 0;
    uint256 wethIdx = 0;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        vm.startPrank(lp);
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        poolA = new PoolMock(IVault(address(vault)), "ERC20 Pool - DAI/USDC", "ERC20_POOL_DAI_USDC");
        vm.label(address(poolA), "poolA");
        factoryMock.registerTestPool(address(poolA), tokenConfig, poolHooksContract, lp);
        _initPool(
            address(poolA),
            [poolInitialAmount, poolInitialAmount].toMemoryArray(),
            poolInitialAmount * 2 - MIN_BPT
        );

        IERC20(address(poolA)).approve(address(permit2), type(uint256).max);
        permit2.approve(address(poolA), address(router), type(uint160).max, type(uint48).max);

        (poolAIdx, wethIdx) = getSortedIndexes(address(poolA), address(weth));

        tokenConfig = vault.buildTokenConfig([address(poolA), address(weth)].toMemoryArray().asIERC20());
        poolB = new PoolMock(IVault(address(vault)), "ERC20 Pool - poolA/wETH", "ERC20_POOL_POOLA_WETH");
        vm.label(address(poolB), "poolB");
        factoryMock.registerTestPool(address(poolB), tokenConfig, poolHooksContract);
        _initPool(
            address(poolB),
            [poolInitialAmount, poolInitialAmount].toMemoryArray(),
            poolInitialAmount * 2 - MIN_BPT
        );

        vm.stopPrank();

        vm.startPrank(alice);
        IERC20(address(poolA)).approve(address(router), type(uint256).max);
        IERC20(address(poolA)).approve(address(permit2), type(uint256).max);
        permit2.approve(address(poolA), address(router), type(uint160).max, type(uint48).max);

        IERC20(address(poolB)).approve(address(router), type(uint256).max);
        IERC20(address(poolB)).approve(address(permit2), type(uint256).max);
        permit2.approve(address(poolB), address(router), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function testAddLiquidityAndSwapSingleTokenExactIn() public {
        vm.startPrank(alice);

        (, , uint256[] memory beforeBalancesRaw, ) = vault.getPoolTokenInfo(address(poolB));

        uint256 exactBptAmount = poolInitialAmount;
        uint256[] memory maxAmountsIn = [MAX_UINT128, MAX_UINT128].toMemoryArray();

        router.addLiquidityProportional(address(poolA), maxAmountsIn, exactBptAmount, false, bytes(""));

        (, , uint256[] memory afterAddLiquidityBalancesRaw, ) = vault.getPoolTokenInfo(address(poolB));
        for (uint256 i = 0; i < beforeBalancesRaw.length; i++) {
            assertEq(beforeBalancesRaw[i], afterAddLiquidityBalancesRaw[i], "Balances should not change");
        }

        assertEq(poolA.balanceOf(alice), exactBptAmount, "Alice PoolA BPT balance should be increased");

        uint256 amountOut = router.swapSingleTokenExactIn(
            address(poolB),
            IERC20(address(poolA)),
            weth,
            exactBptAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        (, , uint256[] memory afterSwapBalancesRaw, ) = vault.getPoolTokenInfo(address(poolB));
        assertEq(
            afterSwapBalancesRaw[poolAIdx],
            beforeBalancesRaw[poolAIdx] + exactBptAmount,
            "PoolA BPT token balance in poolB should increase"
        );
        assertEq(
            afterSwapBalancesRaw[wethIdx],
            beforeBalancesRaw[wethIdx] - amountOut,
            "WETH token balance in poolB should decrease"
        );
        assertEq(poolA.balanceOf(alice), 0, "Alice PoolA BPT balance should be decreased");

        vm.stopPrank();
    }

    function testAddLiquidityAndSwapSingleTokenExactOut() public {
        vm.startPrank(alice);

        (, , uint256[] memory beforeBalancesRaw, ) = vault.getPoolTokenInfo(address(poolB));

        uint256 exactBptAmount = poolInitialAmount;
        uint256[] memory maxAmountsIn = [MAX_UINT128, MAX_UINT128].toMemoryArray();

        router.addLiquidityProportional(address(poolA), maxAmountsIn, exactBptAmount, false, bytes(""));

        (, , uint256[] memory afterAddLiquidityBalancesRaw, ) = vault.getPoolTokenInfo(address(poolB));
        for (uint256 i = 0; i < beforeBalancesRaw.length; i++) {
            assertEq(beforeBalancesRaw[i], afterAddLiquidityBalancesRaw[i], "Balances should not change");
        }

        assertEq(poolA.balanceOf(alice), exactBptAmount, "Alice PoolA BPT balance should be increased");

        uint256 amountOut = poolInitialAmount;
        uint256 bptAmountIn = router.swapSingleTokenExactOut(
            address(poolB),
            IERC20(address(poolA)),
            weth,
            poolInitialAmount,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        assertEq(bptAmountIn, exactBptAmount, "BPT amount in should be equal to exactBptAmount");

        (, , uint256[] memory afterSwapBalancesRaw, ) = vault.getPoolTokenInfo(address(poolB));
        assertEq(
            afterSwapBalancesRaw[poolAIdx],
            beforeBalancesRaw[poolAIdx] + exactBptAmount,
            "PoolA BPT token balance in poolB should increase"
        );
        assertEq(
            afterSwapBalancesRaw[wethIdx],
            beforeBalancesRaw[wethIdx] - amountOut,
            "WETH token balance in poolB should decrease"
        );
        assertEq(poolA.balanceOf(alice), 0, "Alice PoolA BPT balance should be decreased");

        vm.stopPrank();
    }
}
