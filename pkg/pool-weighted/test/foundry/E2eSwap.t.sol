// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";
import { E2eSwapTest } from "@balancer-labs/v3-vault/test/foundry/E2eSwap.t.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";
import { WeightedPoolMock } from "../../contracts/test/WeightedPoolMock.sol";
import { WeightedPoolContractsDeployer } from "./utils/WeightedPoolContractsDeployer.sol";

contract E2eSwapWeightedTest is E2eSwapTest, WeightedPoolContractsDeployer {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%

    uint256 internal poolCreationNonce;

    function setUp() public override {
        E2eSwapTest.setUp();

        // Set swap fees to min swap fee percentage.
        vault.manualSetStaticSwapFeePercentage(pool, IBasePool(pool).getMinimumSwapFeePercentage());

        vm.prank(poolCreator);
        // Weighted pools may be drained if there are no lp fees. So, set the creator fee to 99% to add some lp fee
        // back to the pool and ensure the invariant doesn't decrease.
        feeController.setPoolCreatorSwapFeePercentage(pool, 99e16);
    }

    function setUpVariables() internal override {
        sender = lp;
        poolCreator = lp;

        // 0.0001% max swap fee.
        minPoolSwapFeePercentage = 1e12;
        // 10% max swap fee.
        maxPoolSwapFeePercentage = 10e16;
    }

    function calculateMinAndMaxSwapAmounts() internal override {
        minSwapAmountTokenA = poolInitAmountTokenA / 1e3;
        minSwapAmountTokenB = poolInitAmountTokenB / 1e3;

        // Divide init amount by 10 to make sure weighted math ratios are respected (Cannot trade more than 30% of pool
        // balance).
        maxSwapAmountTokenA = poolInitAmountTokenA / 10;
        maxSwapAmountTokenB = poolInitAmountTokenB / 10;
    }

    function fuzzPoolParams(uint256[POOL_SPECIFIC_PARAMS_SIZE] memory params) internal override {
        uint256 weightTokenA = params[0];
        weightTokenA = bound(weightTokenA, 0.1e16, 99.9e16);

        uint256[] memory newPoolBalances = _setPoolBalancesWithDifferentWeights(weightTokenA);
        _setMinAndMaxSwapAmountExactIn(newPoolBalances);
        _setMinAndMaxSwapAmountExactOut(newPoolBalances);

        // Weighted Pool has rounding errors when token decimals are different, so the number below fixes the test
        // `testExactInRepeatExactOutVariableFeesSpecific__Fuzz`. The farther from 50/50 weights, the bigger the error.
        exactInOutDecimalsErrorMultiplier = 2000;
    }

    function _setMinAndMaxSwapAmountExactIn(uint256[] memory poolBalancesRaw) private {
        // Since tokens can have different decimals and amountIn is in relation to tokenA, normalize tokenB liquidity.
        uint256 normalizedLiquidityTokenB = (poolBalancesRaw[tokenBIdx] * (10 ** decimalsTokenA)) /
            (10 ** decimalsTokenB);

        // 25% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
        maxSwapAmountTokenA =
            (
                poolBalancesRaw[tokenAIdx] > normalizedLiquidityTokenB
                    ? normalizedLiquidityTokenB
                    : poolBalancesRaw[tokenAIdx]
            ) /
            4;
        // Makes sure minSwapAmount is smaller than maxSwapAmount.
        minSwapAmountTokenA = minSwapAmountTokenA > maxSwapAmountTokenA ? maxSwapAmountTokenA : minSwapAmountTokenA;
    }

    function _setMinAndMaxSwapAmountExactOut(uint256[] memory poolBalancesRaw) private {
        // Since tokens can have different decimals and amountOut is in relation to tokenB, normalize tokenA liquidity.
        uint256 normalizedLiquidityTokenA = (poolBalancesRaw[tokenAIdx] * (10 ** decimalsTokenB)) /
            (10 ** decimalsTokenA);

        // 25% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
        maxSwapAmountTokenB =
            (
                normalizedLiquidityTokenA > poolBalancesRaw[tokenBIdx]
                    ? poolBalancesRaw[tokenBIdx]
                    : normalizedLiquidityTokenA
            ) /
            4;
        // Makes sure minSwapAmount is smaller than maxSwapAmount.
        minSwapAmountTokenB = minSwapAmountTokenB > maxSwapAmountTokenB ? maxSwapAmountTokenB : minSwapAmountTokenB;
    }

    function testSwapSymmetry__Fuzz(uint256 tokenAAmountIn, uint256 weightTokenA, uint256 swapFeePercentage) public {
        weightTokenA = bound(weightTokenA, 1e16, 99e16);
        swapFeePercentage = bound(swapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);
        _setSwapFeePercentage(pool, swapFeePercentage);

        uint256[] memory newPoolBalances = _setPoolBalancesWithDifferentWeights(weightTokenA);

        // Since tokens can have different decimals and amountOut is in relation to tokenB, normalize tokenA liquidity.
        uint256 normalizedLiquidityTokenA = (newPoolBalances[tokenAIdx] * (10 ** decimalsTokenB)) /
            (10 ** decimalsTokenA);

        // Cap amount in to lowest normalized liquidity * 25%
        tokenAAmountIn = bound(
            tokenAAmountIn,
            1e15,
            Math.min(normalizedLiquidityTokenA, newPoolBalances[tokenBIdx]) / 4
        );

        uint256 snapshotId = vm.snapshot();

        vm.prank(alice);
        uint256 amountOut = router.swapSingleTokenExactIn(
            pool,
            tokenA,
            tokenB,
            tokenAAmountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        vm.revertTo(snapshotId);

        vm.prank(alice);
        uint256 amountIn = router.swapSingleTokenExactOut(
            pool,
            tokenA,
            tokenB,
            amountOut,
            MAX_UINT128,
            MAX_UINT256,
            false,
            bytes("")
        );

        // An ExactIn swap with `defaultAmount` tokenIn returned `amountOut` tokenOut.
        // Since Exact_In and Exact_Out are symmetrical, an ExactOut swap with `amountOut` tokenOut should return the
        // same amount of tokenIn.
        assertApproxEqRel(amountIn, tokenAAmountIn, 0.00001e16, "Swap fees are not symmetric for ExactIn and ExactOut");
    }

    /**
     * @notice Creates and initializes a weighted pool with a setter for weights, so weights can be changed without
     * initializing the pool again. This pool is used by E2eSwapTest tests.
     */
    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        LiquidityManagement memory liquidityManagement;
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        WeightedPoolMock weightedPool = deployWeightedPoolMock(
            WeightedPool.NewPoolParams({
                name: label,
                symbol: "WEIGHTY",
                numTokens: 2,
                normalizedWeights: [uint256(50e16), uint256(50e16)].toMemoryArray(),
                version: "Version 1"
            }),
            vault
        );
        vm.label(address(weightedPool), label);

        vault.registerPool(
            address(weightedPool),
            vault.buildTokenConfig(tokens.asIERC20()),
            DEFAULT_SWAP_FEE,
            0,
            false,
            roleAccounts,
            address(0),
            liquidityManagement
        );

        return address(weightedPool);
    }

    function _setPoolBalancesWithDifferentWeights(
        uint256 weightTokenA
    ) private returns (uint256[] memory newPoolBalances) {
        uint256[2] memory newWeights;
        newWeights[tokenAIdx] = weightTokenA;
        newWeights[tokenBIdx] = FixedPoint.ONE - weightTokenA;

        WeightedPoolMock(pool).setNormalizedWeights(newWeights);

        newPoolBalances = new uint256[](2);
        // This operation will change the invariant of the pool, but what matters is the proportion of each token.
        newPoolBalances[tokenAIdx] = (poolInitAmountTokenA).mulDown(newWeights[tokenAIdx]);
        newPoolBalances[tokenBIdx] = (poolInitAmountTokenB).mulDown(newWeights[tokenBIdx]);

        // Rate is 1, so we just need to compare 18 with token decimals to scale each liquidity accordingly.
        uint256[] memory newPoolBalanceLiveScaled18 = new uint256[](2);
        newPoolBalanceLiveScaled18[tokenAIdx] = newPoolBalances[tokenAIdx] * 10 ** (18 - decimalsTokenA);
        newPoolBalanceLiveScaled18[tokenBIdx] = newPoolBalances[tokenBIdx] * 10 ** (18 - decimalsTokenB);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        // liveBalances = rawBalances because rate is 1 and both tokens are 18 decimals.
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalances, newPoolBalanceLiveScaled18);
    }

    function _calculatePoolInvariant(
        address poolToCalculate,
        Rounding rounding
    ) private view returns (uint256 invariant) {
        (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(poolToCalculate);
        return IBasePool(poolToCalculate).computeInvariant(lastBalancesLiveScaled18, rounding);
    }
}
