// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { PoolConfigBits } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { BaseVaultTest } from "../../utils/BaseVaultTest.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import {
    AddLiquidityParams,
    AddLiquidityKind,
    RemoveLiquidityParams,
    RemoveLiquidityKind,
    SwapParams,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfigLib } from "../../../../contracts/lib/PoolConfigLib.sol";

contract VaultMutationTest is BaseVaultTest {
    using ArrayHelpers for *;
    using ScalingHelpers for *;
    using PoolConfigLib for PoolConfigBits;

    struct TestAddLiquidityParams {
        AddLiquidityParams addLiquidityParams;
        uint256[] expectedAmountsInScaled18;
        uint256[] maxAmountsInScaled18;
        uint256[] expectSwapFeeAmountsScaled18;
        uint256 expectedBPTAmountOut;
    }

    struct TestRemoveLiquidityParams {
        RemoveLiquidityParams removeLiquidityParams;
        uint256[] expectedAmountsOutScaled18;
        uint256[] minAmountsOutScaled18;
        uint256[] expectSwapFeeAmountsScaled18;
        uint256 expectedBPTAmountIn;
    }

    uint256 immutable defaultAmountGivenRaw = 1e18;

    IERC20[] swapTokens;
    uint256[] initialBalances = [uint256(10e18), 10e18];
    uint256[] decimalScalingFactors = [uint256(1e18), 1e18];
    uint256[] tokenRates = [uint256(1e18), 2e18];
    uint256 initTotalSupply = 1000e18;

    address internal constant ZERO_ADDRESS = address(0x00);

    uint256[] internal amountsIn = [poolInitAmount, poolInitAmount].toMemoryArray();

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        swapTokens = [dai, usdc];

        vault.mintERC20(pool, address(this), initTotalSupply);
    }

    function testSettleWithLockedVault() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultIsNotUnlocked.selector));
        vault.settle(dai);
    }

    function testSendToWithLockedVault() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultIsNotUnlocked.selector));
        vault.sendTo(dai, address(0), 1);
    }

    function testSwapWithLockedVault() public {
        SwapParams memory params = SwapParams(SwapKind.EXACT_IN, address(pool), dai, usdc, 1, 0, bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultIsNotUnlocked.selector));
        vault.swap(params);
    }

    function testAddLiquidityWithLockedVault() public {
        AddLiquidityParams memory params = AddLiquidityParams(
            address(pool),
            address(0),
            amountsIn,
            0,
            AddLiquidityKind.PROPORTIONAL,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultIsNotUnlocked.selector));
        vault.addLiquidity(params);
    }

    function testRemoveLiquidityWithLockedVault() public {
        RemoveLiquidityParams memory params = RemoveLiquidityParams(
            address(pool),
            address(0),
            0,
            amountsIn,
            RemoveLiquidityKind.PROPORTIONAL,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultIsNotUnlocked.selector));
        vault.removeLiquidity(params);
    }

    function testSwapReentrancy() public {
        (SwapParams memory params, SwapState memory state, PoolData memory poolData) = _makeParams(
            SwapKind.EXACT_OUT,
            defaultAmountGivenRaw,
            0,
            0
        );

        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuardReentrantCall()"));
        vault.manualReentrancySwap(params, state, poolData);
    }

    function testAddLiquidityReentrancy() public {
        PoolData memory poolData = _makeDefaultParams();
        (AddLiquidityParams memory params1, uint256[] memory maxAmountsInScaled18) = _makeAddLiquidityParams(
            poolData,
            AddLiquidityKind.PROPORTIONAL,
            1e18
        );

        TestAddLiquidityParams memory params = TestAddLiquidityParams({
            addLiquidityParams: params1,
            expectedAmountsInScaled18: BasePoolMath.computeProportionalAmountsIn(
                poolData.balancesLiveScaled18,
                vault.totalSupply(params1.pool),
                params1.minBptAmountOut
            ),
            maxAmountsInScaled18: maxAmountsInScaled18,
            expectSwapFeeAmountsScaled18: new uint256[](tokens.length),
            expectedBPTAmountOut: params1.minBptAmountOut
        });

        uint256[] memory expectedAmountsInRaw = new uint256[](params.expectedAmountsInScaled18.length);
        for (uint256 i = 0; i < expectedAmountsInRaw.length; i++) {
            expectedAmountsInRaw[i] = params.expectedAmountsInScaled18[i].toRawUndoRateRoundUp(
                poolData.decimalScalingFactors[i],
                poolData.tokenRates[i]
            );
        }

        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuardReentrantCall()"));
        vault.manualReentrancyAddLiquidity(poolData, params.addLiquidityParams, params.maxAmountsInScaled18);
    }

    function testRemoveLiquidityReentrancy() public {
        PoolData memory poolData = _makeDefaultParams();
        VaultState memory vaultState;

        (RemoveLiquidityParams memory params1, uint256[] memory minAmountsOutScaled18) = _makeRemoveLiquidityParams(
            poolData,
            RemoveLiquidityKind.PROPORTIONAL,
            1e18,
            1
        );

        TestRemoveLiquidityParams memory params = TestRemoveLiquidityParams({
            removeLiquidityParams: params1,
            expectedAmountsOutScaled18: BasePoolMath.computeProportionalAmountsOut(
                poolData.balancesLiveScaled18,
                vault.totalSupply(params1.pool),
                params1.maxBptAmountIn
            ),
            minAmountsOutScaled18: minAmountsOutScaled18,
            expectSwapFeeAmountsScaled18: new uint256[](tokens.length),
            expectedBPTAmountIn: params1.maxBptAmountIn
        });

        uint256[] memory expectedAmountsOutRaw = new uint256[](params.expectedAmountsOutScaled18.length);
        for (uint256 i = 0; i < expectedAmountsOutRaw.length; i++) {
            expectedAmountsOutRaw[i] = params.expectedAmountsOutScaled18[i].toRawUndoRateRoundDown(
                poolData.decimalScalingFactors[i],
                poolData.tokenRates[i]
            );
        }

        vm.prank(pool);
        vault.approve(params.removeLiquidityParams.from, address(this), params.expectedBPTAmountIn);

        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuardReentrantCall()"));
        vault.manualReentrancyRemoveLiquidity(poolData, params.removeLiquidityParams, params.minAmountsOutScaled18);
    }

    /// Helper functions

    function _makeParams(
        SwapKind kind,
        uint256 amountGivenRaw,
        uint256 limitRaw,
        uint256 swapFeePercentage
    ) internal view returns (SwapParams memory params, SwapState memory swapState, PoolData memory poolData) {
        params = SwapParams({
            kind: kind,
            pool: pool,
            tokenIn: swapTokens[0],
            tokenOut: swapTokens[1],
            amountGivenRaw: amountGivenRaw,
            limitRaw: limitRaw,
            userData: new bytes(0)
        });

        swapState.indexIn = 0;
        swapState.indexOut = 1;
        swapState.swapFeePercentage = swapFeePercentage;
        swapState.amountGivenScaled18 = amountGivenRaw.toScaled18ApplyRateRoundDown(
            decimalScalingFactors[kind == SwapKind.EXACT_IN ? swapState.indexIn : swapState.indexOut],
            tokenRates[kind == SwapKind.EXACT_IN ? swapState.indexIn : swapState.indexOut]
        );

        poolData.decimalScalingFactors = decimalScalingFactors;
        poolData.tokenRates = tokenRates;
        poolData.balancesRaw = initialBalances;

        poolData.poolConfigBits = poolData.poolConfigBits.setStaticSwapFeePercentage(swapFeePercentage);

        poolData.balancesLiveScaled18 = new uint256[](initialBalances.length);
    }

    function _makeDefaultParams() internal view returns (PoolData memory poolData) {
        poolData.poolConfigBits = poolData.poolConfigBits.setStaticSwapFeePercentage(swapFeePercentage);

        poolData.balancesLiveScaled18 = new uint256[](tokens.length);
        poolData.balancesRaw = new uint256[](tokens.length);

        poolData.tokenInfo = new TokenInfo[](tokens.length);
        poolData.decimalScalingFactors = new uint256[](tokens.length);
        poolData.tokenRates = new uint256[](tokens.length);
        poolData.tokens = new IERC20[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            poolData.tokens[i] = tokens[i];
            poolData.decimalScalingFactors[i] = 1e18;
            poolData.tokenRates[i] = 1e18 * (i + 1);

            poolData.balancesLiveScaled18[i] = 1000e18;
            poolData.balancesRaw[i] = poolData.balancesLiveScaled18[i].toRawUndoRateRoundDown(
                poolData.decimalScalingFactors[i],
                poolData.tokenRates[i]
            );
        }
    }

    function _makeAddLiquidityParams(
        PoolData memory poolData,
        AddLiquidityKind kind,
        uint256 minBptAmountOut
    ) internal view returns (AddLiquidityParams memory params, uint256[] memory maxAmountsInScaled18) {
        params = AddLiquidityParams({
            pool: pool,
            to: address(this),
            kind: kind,
            maxAmountsIn: new uint256[](tokens.length),
            minBptAmountOut: minBptAmountOut,
            userData: new bytes(0)
        });

        maxAmountsInScaled18 = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            maxAmountsInScaled18[i] = 1e18;
            params.maxAmountsIn[i] = maxAmountsInScaled18[i].toRawUndoRateRoundUp(
                poolData.decimalScalingFactors[i],
                poolData.tokenRates[i]
            );
        }
    }

    function _makeRemoveLiquidityParams(
        PoolData memory poolData,
        RemoveLiquidityKind kind,
        uint256 maxBptAmountIn,
        uint256 defaultMinAmountOut
    ) internal view returns (RemoveLiquidityParams memory params, uint256[] memory minAmountsOutScaled18) {
        params = RemoveLiquidityParams({
            pool: pool,
            from: address(this),
            maxBptAmountIn: maxBptAmountIn,
            minAmountsOut: new uint256[](tokens.length),
            kind: kind,
            userData: new bytes(0)
        });

        minAmountsOutScaled18 = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            minAmountsOutScaled18[i] = defaultMinAmountOut;
            params.minAmountsOut[i] = minAmountsOutScaled18[i].toRawUndoRateRoundUp(
                poolData.decimalScalingFactors[i],
                poolData.tokenRates[i]
            );
        }
    }
}
