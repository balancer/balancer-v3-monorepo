// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
import { VaultExtensionMock } from "@balancer-labs/v3-vault/contracts/test/VaultExtensionMock.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { InputHelpersMock } from "@balancer-labs/v3-vault/contracts/test/InputHelpersMock.sol";

import { PriceImpactHelper } from "../../contracts/PriceImpactHelper.sol";

contract PriceImpactTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    WeightedPoolFactory factory;
    WeightedPool weightedPool;
    PriceImpactHelper priceImpactHelper;

    InputHelpersMock public immutable inputHelpersMock = new InputHelpersMock();

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        priceImpactHelper = new PriceImpactHelper(vault, router);
    }

    function createPool() internal override returns (address, bytes memory) {
        factory = new WeightedPoolFactory(vault, 365 days, "v1", "v1");
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = IERC20(dai);
        tokens[1].token = IERC20(usdc);

        weightedPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                inputHelpersMock.sortTokenConfig(tokens),
                [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                _poolRoleAccounts[pool],
                1e16,
                address(0),
                false,
                false,
                ""
            )
        );
        return (
            address(weightedPool),
            abi.encode(
                WeightedPool.NewPoolParams({
                    name: "ERC20 Pool",
                    symbol: "ERC20POOL",
                    numTokens: tokens.length,
                    normalizedWeights: [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                    version: ""
                }),
                vault
            )
        );
    }

    function testPriceImpact() public {
        vm.startPrank(address(0), address(0));
        uint256 snapshot = vm.snapshot();

        // Calculate priceImpact.
        uint256 amountIn = poolInitAmount / 2;
        uint256[] memory amountsIn = [amountIn, 0].toMemoryArray();

        uint256 priceImpact = priceImpactHelper.calculateAddLiquidityUnbalancedPriceImpact(pool, amountsIn, address(0));
        vm.revertTo(snapshot);

        // It's tricky to choose an infinitesimal amount to calculate the spot price. A very low amount doesn't have
        // enough resolution to calculate the price of the BPT properly, while a big amount doesn't calculate the spot
        // price accurately enough, since the price already suffers an impact.
        // The value below was chosen empirically, and is the value that calculates the spot price in the most accurate
        // way for the current scenario.
        uint256 infinitesimalAmountIn = 5e9;

        uint256 infinitesimalBptOut = router.queryAddLiquidityUnbalanced(
            pool,
            [infinitesimalAmountIn, 0].toMemoryArray(),
            address(0),
            bytes("")
        );
        vm.revertTo(snapshot);

        uint256 spotPrice = infinitesimalAmountIn.divDown(infinitesimalBptOut);

        // Calculate effectivePrice.
        uint256 bptOut = router.queryAddLiquidityUnbalanced(pool, amountsIn, address(0), bytes(""));
        uint256 effectivePrice = amountIn.divDown(bptOut);

        // Calculate expectedPriceImpact for comparison.
        uint256 expectedPriceImpact = effectivePrice.divDown(spotPrice) - 1e18;

        // Assert within acceptable bounds of +-1%. The error is a bit high because of the spot price calculation,
        // which is not very accurate.
        assertApproxEqRel(priceImpact, expectedPriceImpact, 1e16, "Price impact greater than expected");

        vm.stopPrank();
    }
}
