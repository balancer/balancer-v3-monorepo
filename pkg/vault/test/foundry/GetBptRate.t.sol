// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract GetBptRateTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    WeightedPoolFactory factory;
    uint256[] internal weights;
    uint256 internal initBptAmountOut;

    uint256 private daiMockRate = 1.5e18;
    uint256 private usdcMockRate = 0.5e18;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function _createPool(address[] memory tokens, string memory label) internal virtual override returns (address) {
        PoolRoleAccounts memory roleAccounts;

        factory = new WeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Weighted Pool v1");
        weights = [uint256(0.50e18), uint256(0.50e18)].toMemoryArray();

        RateProviderMock rateProviderDai = new RateProviderMock();
        rateProviderDai.mockRate(daiMockRate);
        RateProviderMock rateProviderUsdc = new RateProviderMock();
        rateProviderUsdc.mockRate(usdcMockRate);

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = IRateProvider(rateProviderDai);
        rateProviders[1] = IRateProvider(rateProviderUsdc);

        WeightedPool newPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                vault.buildTokenConfig(tokens.asIERC20(), rateProviders),
                weights,
                roleAccounts,
                swapFeePercentage,
                address(0), // No hook contract
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                ZERO_BYTES32
            )
        );
        vm.label(address(newPool), label);
        return address(newPool);
    }

    function initPool() internal override {
        vm.startPrank(lp);
        initBptAmountOut = _initPool(pool, [defaultAmount, defaultAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    function testGetBptRateWithRateProvider() public {
        uint256 totalSupply = initBptAmountOut + MIN_BPT;
        uint256[] memory liveBalances = [defaultAmount.mulDown(daiMockRate), defaultAmount.mulDown(usdcMockRate)]
            .toMemoryArray();
        uint256 weightedInvariant = WeightedMath.computeInvariant(weights, liveBalances);
        uint256 expectedRate = weightedInvariant.divDown(totalSupply);
        uint256 actualRate = vault.getBptRate(pool);
        assertEq(actualRate, expectedRate, "Wrong rate");

        uint256[] memory amountsIn = [defaultAmount, 0].toMemoryArray();
        vm.prank(bob);
        uint256 addLiquidityBptAmountOut = router.addLiquidityUnbalanced(pool, amountsIn, 0, false, bytes(""));

        totalSupply += addLiquidityBptAmountOut;
        liveBalances = [2 * defaultAmount.mulDown(daiMockRate), defaultAmount.mulDown(usdcMockRate)].toMemoryArray();
        weightedInvariant = WeightedMath.computeInvariant(weights, liveBalances);

        expectedRate = weightedInvariant.divDown(totalSupply);
        actualRate = vault.getBptRate(pool);
        assertEq(actualRate, expectedRate, "Wrong rate after addLiquidity");
    }
}
