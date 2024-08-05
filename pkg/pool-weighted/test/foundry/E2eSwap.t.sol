// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

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

contract E2eSwapWeightedTest is E2eSwapTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%

    uint256 internal poolCreationNonce;

    WeightedPoolMock internal poolWithMutableWeights;

    function setUp() public override {
        E2eSwapTest.setUp();
        poolWithMutableWeights = WeightedPoolMock(_createAndInitPoolWithMutableWeights());

        // Set swap fees to 0.0001% (Min swap fee percentage of weighted pools).
        vault.manualSetStaticSwapFeePercentage(address(poolWithMutableWeights), 1e12);

        vm.prank(poolCreator);
        // Weighted pools may be drained if there are no lp fees. So, set the creator fee to 99% to add some lp fee
        // back to the pool and ensure the invariant doesn't decrease.
        feeController.setPoolCreatorSwapFeePercentage(address(poolWithMutableWeights), 99e16);
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

    function testDoUndoExactInDifferentWeights(uint256 weightTokenA) public {
        // Vary from 0.1% to 99.9%.
        weightTokenA = bound(weightTokenA, 0.1e16, 99.9e16);

        uint256[] memory newPoolBalances = _setPoolBalancesWithDifferentWeights(weightTokenA);

        // Since tokens can have different decimals and amountIn is in relation to tokenA, normalize tokenB liquidity.
        uint256 normalizedLiquidityTokenB = (newPoolBalances[tokenBIdx] * (10 ** decimalsTokenA)) /
            (10 ** decimalsTokenB);

        // 25% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
        uint256 exactAmountIn = (
            newPoolBalances[tokenAIdx] > normalizedLiquidityTokenB
                ? normalizedLiquidityTokenB
                : newPoolBalances[tokenAIdx]
        ) / 4;

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);
        // `BaseVaultTest.getBalances` checks the poolInvariant of `pool`. In this test, a different pool is used, so
        // poolInvariant should be overwritten.
        balancesBefore.poolInvariant = _calculatePoolInvariant(address(poolWithMutableWeights));

        vm.startPrank(sender);
        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
            address(poolWithMutableWeights),
            tokenA,
            tokenB,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 feesTokenB = vault.getAggregateSwapFeeAmount(pool, tokenB);

        // In the first swap, the trade was exactAmountIn => exactAmountOutDo + feesTokenB. So, if
        // there were no fees, trading `exactAmountOutDo + feesTokenB` would get exactAmountIn. Therefore, a swap
        // with exact_in `exactAmountOutDo + feesTokenB` is comparable to `exactAmountIn`, given that the fees are
        // known.
        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            address(poolWithMutableWeights),
            tokenB,
            tokenA,
            exactAmountOutDo + feesTokenB,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(pool, tokenA);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);
        // `BaseVaultTest.getBalances` checks the poolInvariant of `pool`. In this test, a different pool is used, so
        // poolInvariant should be overwritten.
        balancesAfter.poolInvariant = _calculatePoolInvariant(address(poolWithMutableWeights));

        assertLe(exactAmountOutUndo, exactAmountIn - feesTokenA, "Amount out undo should be <= exactAmountIn");

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter, feesTokenA, feesTokenB);
    }

    function testDoUndoExactOutDifferentWeights(uint256 weightTokenA) public {
        // Vary from 0.1% to 99.9%.
        weightTokenA = bound(weightTokenA, 0.1e16, 99.9e16);

        uint256[] memory newPoolBalances = _setPoolBalancesWithDifferentWeights(weightTokenA);

        // Since tokens can have different decimals and amountOut is in relation to tokenB, normalize tokenA liquidity.
        uint256 normalizedLiquidityTokenA = (newPoolBalances[tokenAIdx] * (10 ** decimalsTokenB)) /
            (10 ** decimalsTokenA);

        // 25% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
        uint256 exactAmountOut = (
            normalizedLiquidityTokenA > newPoolBalances[tokenBIdx]
                ? newPoolBalances[tokenBIdx]
                : normalizedLiquidityTokenA
        ) / 4;

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);
        // `BaseVaultTest.getBalances` checks the poolInvariant of `pool`. In this test, a different pool is used, so
        // poolInvariant should be overwritten.
        balancesBefore.poolInvariant = _calculatePoolInvariant(address(poolWithMutableWeights));

        vm.startPrank(sender);
        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
            address(poolWithMutableWeights),
            tokenA,
            tokenB,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(pool, tokenA);

        // In the first swap, the trade was exactAmountInDo => exactAmountOut (tokenB) + feesTokenA (tokenA). So, if
        // there were no fees, trading `exactAmountInDo - feesTokenA` would get exactAmountOut. Therefore, a swap
        // with exact_out `exactAmountInDo - feesTokenA` is comparable to `exactAmountOut`, given that the fees are
        // known.
        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            address(poolWithMutableWeights),
            tokenB,
            tokenA,
            exactAmountInDo - feesTokenA,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesTokenB = vault.getAggregateSwapFeeAmount(pool, tokenB);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);
        // `BaseVaultTest.getBalances` checks the poolInvariant of `pool`. In this test, a different pool is used, so
        // poolInvariant should be overwritten.
        balancesAfter.poolInvariant = _calculatePoolInvariant(address(poolWithMutableWeights));

        assertGe(exactAmountInUndo, exactAmountOut + feesTokenB, "Amount in undo should be >= exactAmountOut");

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter, feesTokenA, feesTokenB);
    }

    /// @notice Overrides BaseVaultTest _createPool(). This pool is used by E2eSwapTest tests.
    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        WeightedPoolFactory factory = new WeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            "Pool v1"
        );
        PoolRoleAccounts memory roleAccounts;

        // Allow pools created by `factory` to use poolHooksMock hooks.
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        WeightedPool newPool = WeightedPool(
            factory.create(
                "50/50 Weighted Pool",
                "50_50WP",
                vault.buildTokenConfig(tokens.asIERC20()),
                [uint256(50e16), uint256(50e16)].toMemoryArray(),
                roleAccounts,
                DEFAULT_SWAP_FEE, // 1% swap fee, but test will override it
                poolHooksContract,
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                // NOTE: sends a unique salt.
                bytes32(poolCreationNonce++)
            )
        );
        vm.label(address(newPool), label);

        // Cannot set the pool creator directly on a standard Balancer weighted pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        feeController.manualSetPoolCreator(address(newPool), lp);

        return address(newPool);
    }

    /**
     * @notice Creates and initializes a weighted pool with a setter for weights, so weights can be changed without
     * initializing the pool again. This pool is used by fuzz tests that require changing the weight.
     */
    function _createAndInitPoolWithMutableWeights() internal returns (address) {
        address[] memory tokens = new address[](2);
        tokens[tokenAIdx] = address(tokenA);
        tokens[tokenBIdx] = address(tokenB);
        string memory label = "ChangeableWeightPool";

        LiquidityManagement memory liquidityManagement;
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = poolCreator;

        WeightedPoolMock weightedPool = new WeightedPoolMock(
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

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[tokenAIdx] = poolInitAmountTokenA;
        amountsIn[tokenBIdx] = poolInitAmountTokenB;

        vm.prank(lp);
        router.initialize(address(weightedPool), tokens.asIERC20(), amountsIn, 0, false, "");

        return address(weightedPool);
    }

    function _setPoolBalancesWithDifferentWeights(
        uint256 weightTokenA
    ) private returns (uint256[] memory newPoolBalances) {
        uint256[2] memory newWeights;
        newWeights[tokenAIdx] = weightTokenA;
        newWeights[tokenBIdx] = FixedPoint.ONE - weightTokenA;

        poolWithMutableWeights.setNormalizedWeights(newWeights);

        newPoolBalances = new uint256[](2);
        // This operation will change the invariant of the pool, but what matters is the proportion of each token.
        newPoolBalances[tokenAIdx] = (poolInitAmountTokenA).mulDown(newWeights[tokenAIdx]);
        newPoolBalances[tokenBIdx] = (poolInitAmountTokenB).mulDown(newWeights[tokenBIdx]);

        // Rate is 1, so we just need to compare 18 with token decimals to scale each liquidity accordingly.
        uint256[] memory newPoolBalanceLiveScaled18 = new uint256[](2);
        newPoolBalanceLiveScaled18[tokenAIdx] = newPoolBalances[tokenAIdx] * 10 ** (18 - decimalsTokenA);
        newPoolBalanceLiveScaled18[tokenBIdx] = newPoolBalances[tokenBIdx] * 10 ** (18 - decimalsTokenB);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(poolWithMutableWeights));
        // liveBalances = rawBalances because rate is 1 and both tokens are 18 decimals.
        vault.manualSetPoolTokensAndBalances(
            address(poolWithMutableWeights),
            tokens,
            newPoolBalances,
            newPoolBalanceLiveScaled18
        );
    }

    function _calculatePoolInvariant(address poolToCalculate) private view returns (uint256 invariant) {
        (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(poolToCalculate);
        return IBasePool(poolToCalculate).computeInvariant(lastBalancesLiveScaled18);
    }
}
