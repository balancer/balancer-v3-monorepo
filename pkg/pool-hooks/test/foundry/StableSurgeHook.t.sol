// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";

import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { PoolSwapParams, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StableSurgeHook } from "../../contracts/StableSurgeHook.sol";
import { StableSurgeMedianMathMock } from "../../contracts/test/StableSurgeMedianMathMock.sol";

contract StableSurgeHookTest is BaseVaultTest {
    using ArrayHelpers for *;
    using CastingHelpers for *;
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_AMP_FACTOR = 200;
    uint256 constant DEFAULT_SURGE_THRESHOLD_PERCENTAGE = 30e16; // 30%
    uint256 constant DEFAULT_MAX_SURGE_FEE_PERCENTAGE = 95e16; // 95%
    uint256 constant DEFAULT_POOL_TOKEN_COUNT = 2;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    StablePoolFactory internal stablePoolFactory;
    StableSurgeHook internal stableSurgeHook;

    StableSurgeMedianMathMock stableSurgeMedianMathMock = new StableSurgeMedianMathMock();

    function setUp() public override {
        super.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createHook() internal override returns (address) {
        stablePoolFactory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");

        vm.prank(address(stablePoolFactory));
        stableSurgeHook = new StableSurgeHook(
            vault,
            DEFAULT_MAX_SURGE_FEE_PERCENTAGE,
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE
        );
        vm.label(address(stableSurgeHook), "StableSurgeHook");
        return address(stableSurgeHook);
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        PoolRoleAccounts memory roleAccounts;

        newPool = stablePoolFactory.create(
            "Stable Pool",
            "STABLEPOOL",
            vault.buildTokenConfig(tokens.asIERC20()),
            DEFAULT_AMP_FACTOR,
            roleAccounts,
            swapFeePercentage,
            poolHooksContract,
            false,
            false,
            ZERO_BYTES32
        );
        vm.label(address(newPool), label);

        return (
            address(newPool),
            abi.encode(
                StablePool.NewPoolParams({
                    name: "Stable Pool",
                    symbol: "STABLEPOOL",
                    amplificationParameter: DEFAULT_AMP_FACTOR,
                    version: "Pool v1"
                }),
                vault
            )
        );
    }

    function testSuccessfulRegistry() public view {
        assertEq(
            stableSurgeHook.getSurgeThresholdPercentage(pool),
            DEFAULT_SURGE_THRESHOLD_PERCENTAGE,
            "Surge threshold is wrong"
        );
    }

    function testSwap__Fuzz(uint256 amountGivenScaled18, uint256 swapFeePercentageRaw, uint256 kindRaw) public {
        amountGivenScaled18 = bound(amountGivenScaled18, 1e18, poolInitAmount / 2);
        SwapKind kind = SwapKind(bound(kindRaw, 0, 1));

        vault.manuallySetSwapFee(pool, bound(swapFeePercentageRaw, 0, 1e16));
        swapFeePercentage = vault.getStaticSwapFeePercentage(pool);

        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        if (kind == SwapKind.EXACT_IN) {
            vm.prank(alice);
            router.swapSingleTokenExactIn(pool, usdc, dai, amountGivenScaled18, 0, MAX_UINT256, false, bytes(""));
        } else {
            vm.prank(alice);
            router.swapSingleTokenExactOut(
                pool,
                usdc,
                dai,
                amountGivenScaled18,
                MAX_UINT256,
                MAX_UINT256,
                false,
                bytes("")
            );
        }

        uint256 actualSwapFeePercentage = _calculateFee(
            amountGivenScaled18,
            kind,
            [poolInitAmount, poolInitAmount].toMemoryArray()
        );

        BaseVaultTest.Balances memory balancesAfter = getBalances(alice);

        uint256 actualAmountOut = balancesAfter.aliceTokens[daiIdx] - balancesBefore.aliceTokens[daiIdx];
        uint256 actualAmountIn = balancesBefore.aliceTokens[usdcIdx] - balancesAfter.aliceTokens[usdcIdx];

        uint256 expectedAmountOut;
        uint256 expectedAmountIn;
        if (kind == SwapKind.EXACT_IN) {
            // extract swap fee
            expectedAmountIn = amountGivenScaled18;
            uint256 swapAmount = amountGivenScaled18.mulUp(actualSwapFeePercentage);

            uint256 amountCalculatedScaled18 = StablePool(pool).onSwap(
                PoolSwapParams({
                    kind: kind,
                    indexIn: usdcIdx,
                    indexOut: daiIdx,
                    amountGivenScaled18: expectedAmountIn - swapAmount,
                    balancesScaled18: [poolInitAmount, poolInitAmount].toMemoryArray(),
                    router: address(0),
                    userData: bytes("")
                })
            );

            expectedAmountOut = amountCalculatedScaled18;
        } else {
            expectedAmountOut = amountGivenScaled18;
            uint256 amountCalculatedScaled18 = StablePool(pool).onSwap(
                PoolSwapParams({
                    kind: kind,
                    indexIn: usdcIdx,
                    indexOut: daiIdx,
                    amountGivenScaled18: expectedAmountOut,
                    balancesScaled18: [poolInitAmount, poolInitAmount].toMemoryArray(),
                    router: address(0),
                    userData: bytes("")
                })
            );
            expectedAmountIn =
                amountCalculatedScaled18 +
                amountCalculatedScaled18.mulDivUp(actualSwapFeePercentage, actualSwapFeePercentage.complement());
        }

        assertEq(expectedAmountIn, actualAmountIn, "Amount in should be expectedAmountIn");
        assertEq(expectedAmountOut, actualAmountOut, "Amount out should be expectedAmountOut");
    }

    function _calculateFee(
        uint256 amountGivenScaled18,
        SwapKind kind,
        uint256[] memory balances
    ) internal view returns (uint256) {
        uint256 amountCalculatedScaled18 = StablePool(pool).onSwap(
            PoolSwapParams({
                kind: kind,
                indexIn: usdcIdx,
                indexOut: daiIdx,
                amountGivenScaled18: amountGivenScaled18,
                balancesScaled18: balances,
                router: address(0),
                userData: bytes("")
            })
        );

        uint256[] memory newBalances = new uint256[](balances.length);
        ScalingHelpers.copyToArray(balances, newBalances);

        if (kind == SwapKind.EXACT_IN) {
            newBalances[usdcIdx] += amountGivenScaled18;
            newBalances[daiIdx] -= amountCalculatedScaled18;
        } else {
            newBalances[usdcIdx] += amountCalculatedScaled18;
            newBalances[daiIdx] -= amountGivenScaled18;
        }

        uint256 newTotalImbalance = stableSurgeMedianMathMock.calculateImbalance(newBalances);
        uint256 oldTotalImbalance = stableSurgeMedianMathMock.calculateImbalance(balances);

        if (
            newTotalImbalance == 0 ||
            (newTotalImbalance <= oldTotalImbalance || newTotalImbalance <= DEFAULT_SURGE_THRESHOLD_PERCENTAGE)
        ) {
            return swapFeePercentage;
        }

        return
            swapFeePercentage +
            (stableSurgeHook.getMaxSurgeFeePercentage(pool) - swapFeePercentage).mulDown(
                (newTotalImbalance - DEFAULT_SURGE_THRESHOLD_PERCENTAGE).divDown(
                    DEFAULT_SURGE_THRESHOLD_PERCENTAGE.complement()
                )
            );
    }
}
