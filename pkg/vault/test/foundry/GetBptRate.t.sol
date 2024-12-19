// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract GetBptRateTest is BaseVaultTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    WeightedPoolFactory factory;
    uint256[] internal weights;
    uint256 internal initBptAmountOut;

    uint256 private daiMockRate = 1.5e18;
    uint256 private usdcMockRate = 0.5e18;

    uint256 daiIdx;
    uint256 usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal virtual override returns (address newPool, bytes memory poolArgs) {
        PoolRoleAccounts memory roleAccounts;

        factory = new WeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Weighted Pool v1");
        weights = [uint256(50e16), uint256(50e16)].toMemoryArray();

        RateProviderMock rateProviderDai = deployRateProviderMock();
        rateProviderDai.mockRate(daiMockRate);
        RateProviderMock rateProviderUsdc = deployRateProviderMock();
        rateProviderUsdc.mockRate(usdcMockRate);

        // The rate providers will be sorted along with the tokens, by `buildTokenConfig`.
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = IRateProvider(rateProviderDai);
        rateProviders[1] = IRateProvider(rateProviderUsdc);

        newPool = factory.create(
            "ERC20 Pool",
            "ERC20POOL",
            vault.buildTokenConfig(tokens.asIERC20(), rateProviders),
            weights,
            roleAccounts,
            DEFAULT_SWAP_FEE_PERCENTAGE,
            address(0), // No hook contract
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );
        vm.label(newPool, label);

        poolArgs = abi.encode(
            WeightedPool.NewPoolParams({
                name: "ERC20 Pool",
                symbol: "ERC20POOL",
                numTokens: tokens.length,
                normalizedWeights: weights,
                version: "Weighted Pool v1"
            }),
            vault
        );
    }

    function initPool() internal override {
        vm.startPrank(lp);
        initBptAmountOut = _initPool(pool(), [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(), 0);
        vm.stopPrank();
    }

    function testGetBptRateWithRateProvider() public {
        uint256 totalSupply = initBptAmountOut + POOL_MINIMUM_TOTAL_SUPPLY;
        uint256[] memory liveBalances = new uint256[](2);
        liveBalances[daiIdx] = DEFAULT_AMOUNT.mulDown(daiMockRate);
        liveBalances[usdcIdx] = DEFAULT_AMOUNT.mulDown(usdcMockRate);

        uint256 weightedInvariant = WeightedMath.computeInvariantDown(weights, liveBalances);
        uint256 expectedRate = weightedInvariant.divDown(totalSupply);
        uint256 actualRate = vault.getBptRate(pool());
        assertEq(actualRate, expectedRate, "Wrong rate");

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[daiIdx] = DEFAULT_AMOUNT;

        vm.prank(bob);
        uint256 addLiquidityBptAmountOut = router.addLiquidityUnbalanced(pool(), amountsIn, 0, false, bytes(""));

        totalSupply += addLiquidityBptAmountOut;
        liveBalances[daiIdx] = 2 * DEFAULT_AMOUNT.mulDown(daiMockRate);
        liveBalances[usdcIdx] = DEFAULT_AMOUNT.mulDown(usdcMockRate);

        weightedInvariant = WeightedMath.computeInvariantDown(weights, liveBalances);

        expectedRate = weightedInvariant.divDown(totalSupply);
        actualRate = vault.getBptRate(pool());
        assertEq(actualRate, expectedRate, "Wrong rate after addLiquidity");
    }
}
