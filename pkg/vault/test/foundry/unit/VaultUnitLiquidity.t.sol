// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";

import { PoolConfigLib } from "../../../contracts/lib/PoolConfigLib.sol";
import { VaultStateBits } from "../../../contracts/lib/VaultStateLib.sol";
import { VaultMockDeployer } from "../../../test/foundry/utils/VaultMockDeployer.sol";
import { BalancerPoolToken } from "../../../contracts/BalancerPoolToken.sol";

contract VaultUnitLiquidityTest is BaseTest {
    using CastingHelpers for uint256[];
    using ScalingHelpers for *;
    using FixedPoint for *;
    using PoolConfigLib for PoolConfigBits;

    // #region Test structs

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
    // #endregion

    address internal constant ZERO_ADDRESS = address(0x00);

    IVaultMock internal vault;

    address pool = address(0x1234);
    uint256 initTotalSupply = 1000e18;
    uint256 swapFeePercentage = 1e16;

    function setUp() public virtual override {
        BaseTest.setUp();
        vault = IVaultMock(address(VaultMockDeployer.deploy()));

        _mockMintCallback(alice, initTotalSupply);
        vault.mintERC20(pool, alice, initTotalSupply);

        uint256[] memory initialBalances = new uint256[](tokens.length);
        // We don't care about last live balances, so we set them equal to the raw ones.
        vault.manualSetPoolTokensAndBalances(pool, tokens, initialBalances, initialBalances);

        vault.manualSetPoolRegistered(pool, true);

        for (uint256 i = 0; i < tokens.length; i++) {
            vault.manualSetAggregateSwapFeeAmount(pool, tokens[i], 0);
        }

        // Mock invariant ratio bounds
        vm.mockCall(
            pool,
            abi.encodeWithSelector(IUnbalancedLiquidityInvariantRatioBounds.getMinimumInvariantRatio.selector),
            abi.encode(0)
        );
        vm.mockCall(
            pool,
            abi.encodeWithSelector(IUnbalancedLiquidityInvariantRatioBounds.getMaximumInvariantRatio.selector),
            abi.encode(1_000_000e18)
        );
    }

    // #region AddLiquidity tests
    function testAddLiquidityProportional() public {
        PoolData memory poolData = _makeDefaultParams();
        (AddLiquidityParams memory params, uint256[] memory maxAmountsInScaled18) = _makeAddLiquidityParams(
            poolData,
            AddLiquidityKind.PROPORTIONAL,
            1e18
        );

        _testAddLiquidity(
            poolData,
            TestAddLiquidityParams({
                addLiquidityParams: params,
                expectedAmountsInScaled18: BasePoolMath.computeProportionalAmountsIn(
                    poolData.balancesLiveScaled18,
                    vault.totalSupply(params.pool),
                    params.minBptAmountOut
                ),
                maxAmountsInScaled18: maxAmountsInScaled18,
                expectSwapFeeAmountsScaled18: new uint256[](tokens.length),
                expectedBPTAmountOut: params.minBptAmountOut
            })
        );
    }

    function testAddLiquidityUnbalanced() public {
        PoolData memory poolData = _makeDefaultParams();
        (AddLiquidityParams memory params, uint256[] memory maxAmountsInScaled18) = _makeAddLiquidityParams(
            poolData,
            AddLiquidityKind.UNBALANCED,
            1e18
        );

        // mock invariants
        (uint256 currentInvariant, uint256 newInvariantAndInvariantWithFeesApplied) = (1e16, 1e18);
        vm.mockCall(
            params.pool,
            abi.encodeWithSelector(IBasePool.computeInvariant.selector, poolData.balancesLiveScaled18),
            abi.encode(currentInvariant)
        );

        uint256[] memory newBalances = new uint256[](tokens.length);
        for (uint256 i = 0; i < newBalances.length; i++) {
            newBalances[i] = poolData.balancesLiveScaled18[i] + maxAmountsInScaled18[i];
        }

        vm.mockCall(
            params.pool,
            abi.encodeWithSelector(IBasePool.computeInvariant.selector, newBalances),
            abi.encode(newInvariantAndInvariantWithFeesApplied)
        );

        (uint256 bptAmountOut, uint256[] memory swapFeeAmountsScaled18) = BasePoolMath.computeAddLiquidityUnbalanced(
            poolData.balancesLiveScaled18,
            maxAmountsInScaled18,
            vault.totalSupply(params.pool),
            swapFeePercentage,
            IBasePool(params.pool)
        );

        _testAddLiquidity(
            poolData,
            TestAddLiquidityParams({
                addLiquidityParams: params,
                expectedAmountsInScaled18: maxAmountsInScaled18,
                maxAmountsInScaled18: maxAmountsInScaled18,
                expectSwapFeeAmountsScaled18: swapFeeAmountsScaled18,
                expectedBPTAmountOut: bptAmountOut
            })
        );
    }

    function testAddLiquiditySingleTokenExactOut() public {
        PoolData memory poolData = _makeDefaultParams();
        (AddLiquidityParams memory params, ) = _makeAddLiquidityParams(
            poolData,
            AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
            1e18
        );

        uint256 tokenInIndex = 0;
        uint256[] memory expectedAmountsInScaled18 = new uint256[](tokens.length);
        uint256[] memory maxAmountsInScaled18 = new uint256[](tokens.length);
        maxAmountsInScaled18[tokenInIndex] = 1e18;
        params.maxAmountsIn[tokenInIndex] = maxAmountsInScaled18[tokenInIndex].toRawUndoRateRoundUp(
            poolData.decimalScalingFactors[tokenInIndex],
            poolData.tokenRates[tokenInIndex]
        );

        uint256 totalSupply = vault.totalSupply(params.pool);
        uint256 newSupply = totalSupply + params.minBptAmountOut;
        vm.mockCall(
            params.pool,
            abi.encodeWithSelector(
                IBasePool.computeBalance.selector,
                poolData.balancesLiveScaled18,
                tokenInIndex,
                newSupply.divUp(totalSupply)
            ),
            abi.encode(newSupply)
        );

        uint256[] memory swapFeeAmountsScaled18;
        (expectedAmountsInScaled18[0], swapFeeAmountsScaled18) = BasePoolMath.computeAddLiquiditySingleTokenExactOut(
            poolData.balancesLiveScaled18,
            0,
            params.minBptAmountOut,
            totalSupply,
            swapFeePercentage,
            IBasePool(params.pool)
        );

        _testAddLiquidity(
            poolData,
            TestAddLiquidityParams({
                addLiquidityParams: params,
                expectedAmountsInScaled18: expectedAmountsInScaled18,
                maxAmountsInScaled18: maxAmountsInScaled18,
                expectSwapFeeAmountsScaled18: swapFeeAmountsScaled18,
                expectedBPTAmountOut: params.minBptAmountOut
            })
        );
    }

    function testAddLiquidityCustom() public {
        uint256 bptAmountOut = 1e18;

        PoolData memory poolData = _makeDefaultParams();
        (AddLiquidityParams memory params, uint256[] memory maxAmountsInScaled18) = _makeAddLiquidityParams(
            poolData,
            AddLiquidityKind.CUSTOM,
            bptAmountOut
        );

        poolData.poolConfigBits = poolData.poolConfigBits.setAddLiquidityCustom(true);

        uint256[] memory expectedAmountsInScaled18 = new uint256[](tokens.length);
        uint256[] memory expectSwapFeeAmountsScaled18 = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            expectedAmountsInScaled18[i] = 1e18;
            expectSwapFeeAmountsScaled18[i] = 1e16;
        }

        vm.mockCall(
            address(params.pool),
            abi.encodeWithSelector(
                IPoolLiquidity.onAddLiquidityCustom.selector,
                address(this), // Router
                maxAmountsInScaled18,
                params.minBptAmountOut,
                poolData.balancesLiveScaled18,
                params.userData
            ),
            abi.encode(expectedAmountsInScaled18, bptAmountOut, expectSwapFeeAmountsScaled18, params.userData)
        );

        _testAddLiquidity(
            poolData,
            TestAddLiquidityParams({
                addLiquidityParams: params,
                expectedAmountsInScaled18: expectedAmountsInScaled18,
                maxAmountsInScaled18: maxAmountsInScaled18,
                expectSwapFeeAmountsScaled18: expectSwapFeeAmountsScaled18,
                expectedBPTAmountOut: params.minBptAmountOut
            })
        );
    }

    function testRevertIfBptAmountOutBelowMin() public {
        PoolData memory poolData = _makeDefaultParams();
        (AddLiquidityParams memory params, uint256[] memory maxAmountsInScaled18) = _makeAddLiquidityParams(
            poolData,
            AddLiquidityKind.CUSTOM,
            1e18
        );

        poolData.poolConfigBits = poolData.poolConfigBits.setAddLiquidityCustom(true);

        uint256 bptAmountOut = 0;
        vm.mockCall(
            address(params.pool),
            abi.encodeWithSelector(
                IPoolLiquidity.onAddLiquidityCustom.selector,
                address(this), // Router
                maxAmountsInScaled18,
                params.minBptAmountOut,
                poolData.balancesLiveScaled18,
                params.userData
            ),
            abi.encode(new uint256[](tokens.length), bptAmountOut, new uint256[](tokens.length), params.userData)
        );

        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.BptAmountOutBelowMin.selector, bptAmountOut, params.minBptAmountOut)
        );
        vault.manualAddLiquidity(poolData, params, maxAmountsInScaled18);
    }

    function testRevertIfAmountInAboveMax() public {
        PoolData memory poolData = _makeDefaultParams();
        (AddLiquidityParams memory params, uint256[] memory maxAmountsInScaled18) = _makeAddLiquidityParams(
            poolData,
            AddLiquidityKind.CUSTOM,
            1e18
        );

        poolData.poolConfigBits = poolData.poolConfigBits.setAddLiquidityCustom(true);

        uint256[] memory expectedAmountsInScaled18 = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            expectedAmountsInScaled18[i] = maxAmountsInScaled18[i] + 1;
        }

        vm.mockCall(
            address(params.pool),
            abi.encodeWithSelector(
                IPoolLiquidity.onAddLiquidityCustom.selector,
                address(this), // Router
                maxAmountsInScaled18,
                params.minBptAmountOut,
                poolData.balancesLiveScaled18,
                params.userData
            ),
            abi.encode(expectedAmountsInScaled18, params.minBptAmountOut, new uint256[](tokens.length), params.userData)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.AmountInAboveMax.selector,
                tokens[0],
                expectedAmountsInScaled18[0],
                maxAmountsInScaled18[0]
            )
        );
        vault.manualAddLiquidity(poolData, params, maxAmountsInScaled18);
    }

    function testRevertAddLiquidityUnbalancedIfUnbalancedLiquidityIsDisabled() public {
        PoolData memory poolData = _makeDefaultParams();
        (AddLiquidityParams memory params, uint256[] memory maxAmountsInScaled18) = _makeAddLiquidityParams(
            poolData,
            AddLiquidityKind.UNBALANCED,
            1e18
        );

        poolData.poolConfigBits = poolData.poolConfigBits.setDisableUnbalancedLiquidity(true);

        vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
        vault.manualAddLiquidity(poolData, params, maxAmountsInScaled18);
    }

    function testRevertAddLiquiditySingleTokenExactOutIfUnbalancedLiquidityIsDisabled() public {
        PoolData memory poolData = _makeDefaultParams();
        (AddLiquidityParams memory params, uint256[] memory maxAmountsInScaled18) = _makeAddLiquidityParams(
            poolData,
            AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
            1e18
        );

        poolData.poolConfigBits = poolData.poolConfigBits.setDisableUnbalancedLiquidity(true);

        vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
        vault.manualAddLiquidity(poolData, params, maxAmountsInScaled18);
    }

    function testRevertAddLiquidityCustomExactOutIfCustomLiquidityIsDisabled() public {
        PoolData memory poolData = _makeDefaultParams();
        (AddLiquidityParams memory params, uint256[] memory maxAmountsInScaled18) = _makeAddLiquidityParams(
            poolData,
            AddLiquidityKind.CUSTOM,
            1e18
        );

        vm.expectRevert(IVaultErrors.DoesNotSupportAddLiquidityCustom.selector);
        vault.manualAddLiquidity(poolData, params, maxAmountsInScaled18);
    }

    // #endregion

    // #region RemoveLiquidity tests
    function testRemoveLiquidityProportional() public {
        PoolData memory poolData = _makeDefaultParams();
        (RemoveLiquidityParams memory params, uint256[] memory minAmountsOutScaled18) = _makeRemoveLiquidityParams(
            poolData,
            RemoveLiquidityKind.PROPORTIONAL,
            1e18,
            1
        );

        _testRemoveLiquidity(
            poolData,
            TestRemoveLiquidityParams({
                removeLiquidityParams: params,
                expectedAmountsOutScaled18: BasePoolMath.computeProportionalAmountsOut(
                    poolData.balancesLiveScaled18,
                    vault.totalSupply(params.pool),
                    params.maxBptAmountIn
                ),
                minAmountsOutScaled18: minAmountsOutScaled18,
                expectSwapFeeAmountsScaled18: new uint256[](tokens.length),
                expectedBPTAmountIn: params.maxBptAmountIn
            })
        );
    }

    function testRemoveLiquiditySingleTokenExactIn() public {
        PoolData memory poolData = _makeDefaultParams();
        (RemoveLiquidityParams memory params, uint256[] memory minAmountsOutScaled18) = _makeRemoveLiquidityParams(
            poolData,
            RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
            1e18,
            0
        );

        uint256 tokenIndex = 0;
        uint256 expectBPTAmountIn = params.maxBptAmountIn;

        params.minAmountsOut[tokenIndex] = 1e18;
        minAmountsOutScaled18[tokenIndex] = params.minAmountsOut[tokenIndex].toScaled18ApplyRateRoundDown(
            poolData.decimalScalingFactors[tokenIndex],
            poolData.tokenRates[tokenIndex]
        );

        uint256[] memory expectedAmountsOutScaled18 = new uint256[](tokens.length);
        uint256[] memory swapFeeAmountsScaled18 = new uint256[](tokens.length);
        uint256 totalSupply = vault.totalSupply(params.pool);
        uint256 newSupply = totalSupply - expectBPTAmountIn;
        vm.mockCall(
            params.pool,
            abi.encodeWithSelector(
                IBasePool.computeBalance.selector,
                poolData.balancesLiveScaled18,
                tokenIndex,
                newSupply.divUp(totalSupply)
            ),
            abi.encode(newSupply)
        );

        (expectedAmountsOutScaled18[tokenIndex], swapFeeAmountsScaled18) = BasePoolMath
            .computeRemoveLiquiditySingleTokenExactIn(
                poolData.balancesLiveScaled18,
                tokenIndex,
                expectBPTAmountIn,
                totalSupply,
                swapFeePercentage,
                IBasePool(params.pool)
            );

        _testRemoveLiquidity(
            poolData,
            TestRemoveLiquidityParams({
                removeLiquidityParams: params,
                expectedAmountsOutScaled18: expectedAmountsOutScaled18,
                minAmountsOutScaled18: minAmountsOutScaled18,
                expectSwapFeeAmountsScaled18: swapFeeAmountsScaled18,
                expectedBPTAmountIn: expectBPTAmountIn
            })
        );
    }

    function testRemoveLiquiditySingleTokenExactOut() public {
        PoolData memory poolData = _makeDefaultParams();
        (RemoveLiquidityParams memory params, uint256[] memory minAmountsOutScaled18) = _makeRemoveLiquidityParams(
            poolData,
            RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
            type(uint256).max,
            0
        );

        uint256 tokenIndex = 0;
        params.minAmountsOut[tokenIndex] = 2e18;
        minAmountsOutScaled18[tokenIndex] = params.minAmountsOut[tokenIndex].toScaled18ApplyRateRoundDown(
            poolData.decimalScalingFactors[tokenIndex],
            poolData.tokenRates[tokenIndex]
        );

        // mock invariants
        {
            (uint256 currentInvariant, uint256 invariantAndInvariantWithFeesApplied) = (3e8, 3e9);
            vm.mockCall(
                params.pool,
                abi.encodeWithSelector(IBasePool.computeInvariant.selector, poolData.balancesLiveScaled18),
                abi.encode(currentInvariant)
            );

            uint256[] memory newBalances = new uint256[](tokens.length);
            for (uint256 i = 0; i < newBalances.length; i++) {
                newBalances[i] = poolData.balancesLiveScaled18[i];
            }
            newBalances[tokenIndex] -= minAmountsOutScaled18[tokenIndex];

            vm.mockCall(
                params.pool,
                abi.encodeWithSelector(IBasePool.computeInvariant.selector, newBalances),
                abi.encode(invariantAndInvariantWithFeesApplied)
            );

            uint256 taxableAmount = invariantAndInvariantWithFeesApplied.divUp(currentInvariant).mulUp(
                poolData.balancesLiveScaled18[tokenIndex]
            ) - newBalances[tokenIndex];

            uint256 fee = taxableAmount.divUp(swapFeePercentage.complement()) - taxableAmount;
            newBalances[tokenIndex] -= fee;

            uint256 newInvariantAndInvariantWithFeesApplied = 1e5;
            vm.mockCall(
                params.pool,
                abi.encodeWithSelector(IBasePool.computeInvariant.selector, newBalances),
                abi.encode(newInvariantAndInvariantWithFeesApplied)
            );
        }

        (uint256 expectBPTAmountIn, uint256[] memory swapFeeAmountsScaled18) = BasePoolMath
            .computeRemoveLiquiditySingleTokenExactOut(
                poolData.balancesLiveScaled18,
                tokenIndex,
                minAmountsOutScaled18[tokenIndex],
                vault.totalSupply(params.pool),
                swapFeePercentage,
                IBasePool(params.pool)
            );

        _testRemoveLiquidity(
            poolData,
            TestRemoveLiquidityParams({
                removeLiquidityParams: params,
                expectedAmountsOutScaled18: minAmountsOutScaled18,
                minAmountsOutScaled18: minAmountsOutScaled18,
                expectSwapFeeAmountsScaled18: swapFeeAmountsScaled18,
                expectedBPTAmountIn: expectBPTAmountIn
            })
        );
    }

    function testRemoveLiquidityCustom() public {
        PoolData memory poolData = _makeDefaultParams();
        poolData.poolConfigBits = poolData.poolConfigBits.setRemoveLiquidityCustom(true);

        (RemoveLiquidityParams memory params, uint256[] memory minAmountsOutScaled18) = _makeRemoveLiquidityParams(
            poolData,
            RemoveLiquidityKind.CUSTOM,
            type(uint256).max,
            1
        );

        uint256 expectBPTAmountIn = 1e18;

        uint256[] memory expectedAmountsOutScaled18 = new uint256[](tokens.length);
        uint256[] memory expectSwapFeeAmountsScaled18 = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            expectedAmountsOutScaled18[i] = 1e18;
            expectSwapFeeAmountsScaled18[i] = 1e16;
        }

        vm.mockCall(
            address(params.pool),
            abi.encodeWithSelector(
                IPoolLiquidity.onRemoveLiquidityCustom.selector,
                address(this), // router
                params.maxBptAmountIn,
                minAmountsOutScaled18,
                poolData.balancesLiveScaled18,
                params.userData
            ),
            abi.encode(expectBPTAmountIn, expectedAmountsOutScaled18, expectSwapFeeAmountsScaled18, params.userData)
        );

        _testRemoveLiquidity(
            poolData,
            TestRemoveLiquidityParams({
                removeLiquidityParams: params,
                expectedAmountsOutScaled18: expectedAmountsOutScaled18,
                minAmountsOutScaled18: minAmountsOutScaled18,
                expectSwapFeeAmountsScaled18: expectSwapFeeAmountsScaled18,
                expectedBPTAmountIn: expectBPTAmountIn
            })
        );
    }

    function testRevertIfBptAmountInAboveMax() public {
        PoolData memory poolData = _makeDefaultParams();
        (RemoveLiquidityParams memory params, uint256[] memory minAmountsOutScaled18) = _makeRemoveLiquidityParams(
            poolData,
            RemoveLiquidityKind.CUSTOM,
            1e18,
            0
        );
        poolData.poolConfigBits = poolData.poolConfigBits.setRemoveLiquidityCustom(true);

        uint256 bptAmountIn = params.maxBptAmountIn + 1;

        vm.mockCall(
            address(params.pool),
            abi.encodeWithSelector(
                IPoolLiquidity.onRemoveLiquidityCustom.selector,
                address(this), // Router
                params.maxBptAmountIn,
                minAmountsOutScaled18,
                poolData.balancesLiveScaled18,
                params.userData
            ),
            abi.encode(bptAmountIn, new uint256[](tokens.length), new uint256[](tokens.length), params.userData)
        );

        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.BptAmountInAboveMax.selector, bptAmountIn, params.maxBptAmountIn)
        );
        vault.manualRemoveLiquidity(poolData, params, minAmountsOutScaled18);
    }

    function testRevertIfAmountOutBelowMin() public {
        PoolData memory poolData = _makeDefaultParams();
        uint256 defaultMinAmountOut = 1e18;
        (RemoveLiquidityParams memory params, uint256[] memory minAmountsOutScaled18) = _makeRemoveLiquidityParams(
            poolData,
            RemoveLiquidityKind.CUSTOM,
            type(uint256).max,
            defaultMinAmountOut
        );
        poolData.poolConfigBits = poolData.poolConfigBits.setRemoveLiquidityCustom(true);

        uint256 bptAmountIn = 1e18;
        uint256[] memory amountsOutScaled18 = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            amountsOutScaled18[i] = defaultMinAmountOut - 1;
        }

        vm.mockCall(
            address(params.pool),
            abi.encodeWithSelector(
                IPoolLiquidity.onRemoveLiquidityCustom.selector,
                address(this), // Router
                params.maxBptAmountIn,
                minAmountsOutScaled18,
                poolData.balancesLiveScaled18,
                params.userData
            ),
            abi.encode(bptAmountIn, amountsOutScaled18, new uint256[](tokens.length), params.userData)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.AmountOutBelowMin.selector,
                tokens[0],
                amountsOutScaled18[0],
                params.minAmountsOut[0]
            )
        );

        vault.manualRemoveLiquidity(poolData, params, minAmountsOutScaled18);
    }

    function testRevertRemoveLiquidityUnbalancedIfUnbalancedLiquidityIsDisabled() public {
        PoolData memory poolData = _makeDefaultParams();
        (RemoveLiquidityParams memory params, uint256[] memory minAmountsOutScaled18) = _makeRemoveLiquidityParams(
            poolData,
            RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
            type(uint256).max,
            1
        );
        poolData.poolConfigBits = poolData.poolConfigBits.setDisableUnbalancedLiquidity(true);

        vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
        vault.manualRemoveLiquidity(poolData, params, minAmountsOutScaled18);
    }

    function testRevertRemoveLiquiditySingleTokenExactOutIfUnbalancedLiquidityIsDisabled() public {
        PoolData memory poolData = _makeDefaultParams();
        (RemoveLiquidityParams memory params, uint256[] memory minAmountsOutScaled18) = _makeRemoveLiquidityParams(
            poolData,
            RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
            type(uint256).max,
            1
        );
        poolData.poolConfigBits = poolData.poolConfigBits.setDisableUnbalancedLiquidity(true);

        vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
        vault.manualRemoveLiquidity(poolData, params, minAmountsOutScaled18);
    }

    function testRevertRemoveLiquidityCustomExactOutIfCustomLiquidityIsDisabled() public {
        PoolData memory poolData = _makeDefaultParams();
        (RemoveLiquidityParams memory params, uint256[] memory minAmountsOutScaled18) = _makeRemoveLiquidityParams(
            poolData,
            RemoveLiquidityKind.CUSTOM,
            type(uint256).max,
            1
        );

        vm.expectRevert(IVaultErrors.DoesNotSupportRemoveLiquidityCustom.selector);
        vault.manualRemoveLiquidity(poolData, params, minAmountsOutScaled18);
    }

    // #endregion

    // #region Helpers
    function _makeAddLiquidityParams(
        PoolData memory poolData,
        AddLiquidityKind kind,
        uint256 minBptAmountOut
    ) internal view returns (AddLiquidityParams memory params, uint256[] memory maxAmountsInScaled18) {
        params = AddLiquidityParams({
            pool: pool,
            to: alice,
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
            from: alice,
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

    function _makeDefaultParams() internal view returns (PoolData memory poolData) {
        poolData.poolConfigBits = poolData.poolConfigBits.setStaticSwapFeePercentage(swapFeePercentage);

        poolData.balancesLiveScaled18 = new uint256[](tokens.length);
        poolData.balancesRaw = new uint256[](tokens.length);

        poolData.tokens = new IERC20[](tokens.length);
        poolData.decimalScalingFactors = new uint256[](tokens.length);
        poolData.tokenRates = new uint256[](tokens.length);

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

    function _mockMintCallback(address to, uint256 amount) internal {
        vm.mockCall(
            pool,
            abi.encodeWithSelector(BalancerPoolToken.emitTransfer.selector, ZERO_ADDRESS, to, amount),
            new bytes(0)
        );
    }

    function _testAddLiquidity(PoolData memory poolData, TestAddLiquidityParams memory params) internal {
        poolData.poolConfigBits = poolData.poolConfigBits.setAggregateSwapFeePercentage(swapFeePercentage);

        uint256[] memory expectedAmountsInRaw = new uint256[](params.expectedAmountsInScaled18.length);
        for (uint256 i = 0; i < expectedAmountsInRaw.length; i++) {
            expectedAmountsInRaw[i] = params.expectedAmountsInScaled18[i].toRawUndoRateRoundUp(
                poolData.decimalScalingFactors[i],
                poolData.tokenRates[i]
            );
        }

        _mockMintCallback(params.addLiquidityParams.to, params.expectedBPTAmountOut);

        vm.expectEmit();
        emit IVaultEvents.PoolBalanceChanged(
            params.addLiquidityParams.pool,
            params.addLiquidityParams.to,
            expectedAmountsInRaw.unsafeCastToInt256(true)
        );

        (
            PoolData memory updatedPoolData,
            uint256[] memory amountsInRaw,
            uint256[] memory amountsInScaled18,
            uint256 bptAmountOut,

        ) = vault.manualAddLiquidity(poolData, params.addLiquidityParams, params.maxAmountsInScaled18);

        assertEq(bptAmountOut, params.expectedBPTAmountOut, "Unexpected BPT amount out");
        assertEq(
            vault.balanceOf(address(params.addLiquidityParams.pool), alice),
            initTotalSupply + bptAmountOut,
            "Token minted with unexpected amount"
        );

        // NOTE: stack too deep fix
        TestAddLiquidityParams memory params_ = params;
        PoolData memory poolData_ = poolData;
        uint256 protocolSwapFeePercentage = poolData.poolConfigBits.getAggregateSwapFeePercentage();

        for (uint256 i = 0; i < poolData_.tokens.length; i++) {
            assertEq(amountsInRaw[i], expectedAmountsInRaw[i], "Unexpected tokenIn raw amount");
            assertEq(amountsInScaled18[i], params_.expectedAmountsInScaled18[i], "Unexpected tokenIn scaled amount");

            uint256 protocolSwapFeeAmountRaw = _checkProtocolFeeResult(
                poolData_,
                i,
                params_.addLiquidityParams.pool,
                protocolSwapFeePercentage,
                params_.expectSwapFeeAmountsScaled18[i]
            );

            assertEq(
                updatedPoolData.balancesRaw[i],
                poolData_.balancesRaw[i] + amountsInRaw[i] - protocolSwapFeeAmountRaw,
                "Unexpected balancesRaw balance"
            );

            assertEq(vault.getTokenDelta(tokens[i]), int256(amountsInRaw[i]), "Unexpected tokenIn delta");
        }

        _checkSetPoolBalancesResult(
            poolData_,
            vault.getRawBalances(params.addLiquidityParams.pool),
            vault.getLastLiveBalances(params.addLiquidityParams.pool),
            updatedPoolData
        );
    }

    function _testRemoveLiquidity(PoolData memory poolData, TestRemoveLiquidityParams memory params) internal {
        poolData.poolConfigBits = poolData.poolConfigBits.setAggregateSwapFeePercentage(1e16);

        uint256[] memory expectedAmountsOutRaw = new uint256[](params.expectedAmountsOutScaled18.length);
        for (uint256 i = 0; i < expectedAmountsOutRaw.length; i++) {
            expectedAmountsOutRaw[i] = params.expectedAmountsOutScaled18[i].toRawUndoRateRoundDown(
                poolData.decimalScalingFactors[i],
                poolData.tokenRates[i]
            );
        }

        vm.prank(pool);
        vault.approve(params.removeLiquidityParams.from, address(this), params.expectedBPTAmountIn);

        vm.expectEmit();
        emit IVaultEvents.PoolBalanceChanged(
            params.removeLiquidityParams.pool,
            params.removeLiquidityParams.from,
            expectedAmountsOutRaw.unsafeCastToInt256(false)
        );

        (
            PoolData memory updatedPoolData,
            uint256 bptAmountIn,
            uint256[] memory amountsOutRaw,
            uint256[] memory amountsOutScaled18,

        ) = vault.manualRemoveLiquidity(poolData, params.removeLiquidityParams, params.minAmountsOutScaled18);

        assertEq(bptAmountIn, params.expectedBPTAmountIn, "Unexpected BPT amount in");
        assertEq(
            vault.balanceOf(address(params.removeLiquidityParams.pool), alice),
            initTotalSupply - bptAmountIn,
            "Token burned with unexpected amount (balance)"
        );
        assertEq(
            vault.allowance(address(vault), params.removeLiquidityParams.from, address(this)),
            0,
            "Token burned with unexpected amount (allowance)"
        );

        // NOTE: stack too deep fix
        TestRemoveLiquidityParams memory params_ = params;
        PoolData memory poolData_ = poolData;
        uint256 protocolSwapFeePercentage = poolData.poolConfigBits.getAggregateSwapFeePercentage();
        for (uint256 i = 0; i < poolData.tokens.length; i++) {
            // check _computeAndChargeAggregateSwapFees
            uint256 protocolSwapFeeAmountRaw = _checkProtocolFeeResult(
                poolData_,
                i,
                params_.removeLiquidityParams.pool,
                protocolSwapFeePercentage,
                params_.expectSwapFeeAmountsScaled18[i]
            );

            // check balances and amounts
            assertEq(
                updatedPoolData.balancesRaw[i],
                poolData_.balancesRaw[i] - protocolSwapFeeAmountRaw - amountsOutRaw[i],
                "Unexpected balancesRaw balance"
            );
            assertEq(
                amountsOutScaled18[i],
                params_.expectedAmountsOutScaled18[i],
                "Unexpected amountsOutScaled18 amount"
            );
            assertEq(amountsOutRaw[i], expectedAmountsOutRaw[i], "Unexpected tokenOut amount");

            // check _supplyCredit
            assertEq(vault.getTokenDelta(tokens[i]), -int256(amountsOutRaw[i]), "Unexpected tokenOut delta");
        }

        _checkSetPoolBalancesResult(
            poolData_,
            vault.getRawBalances(params_.removeLiquidityParams.pool),
            vault.getLastLiveBalances(params_.removeLiquidityParams.pool),
            updatedPoolData
        );
    }

    function _checkProtocolFeeResult(
        PoolData memory poolData,
        uint256 tokenIndex,
        address pool_,
        uint256 protocolSwapFeePercentage,
        uint256 expectSwapFeeAmountScaled18
    ) internal view returns (uint256 protocolSwapFeeAmountRaw) {
        protocolSwapFeeAmountRaw = expectSwapFeeAmountScaled18.mulUp(protocolSwapFeePercentage).toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[tokenIndex],
            poolData.tokenRates[tokenIndex]
        );
        assertEq(
            vault.getAggregateSwapFeeAmount(pool_, poolData.tokens[tokenIndex]),
            protocolSwapFeeAmountRaw,
            "Unexpected protocol fees"
        );
    }

    function _checkSetPoolBalancesResult(
        PoolData memory poolData,
        uint256[] memory storagePoolBalances,
        uint256[] memory storageLastLiveBalances,
        PoolData memory updatedPoolData
    ) internal pure {
        for (uint256 i = 0; i < poolData.tokens.length; i++) {
            assertEq(storagePoolBalances[i], updatedPoolData.balancesRaw[i], "Unexpected pool balance");

            assertEq(
                storageLastLiveBalances[i],
                updatedPoolData.balancesLiveScaled18[i],
                "Unexpected last live balance"
            );

            assertEq(
                updatedPoolData.balancesLiveScaled18[i],
                storagePoolBalances[i].toScaled18ApplyRateRoundDown(
                    poolData.decimalScalingFactors[i],
                    poolData.tokenRates[i]
                ),
                "Unexpected balancesLiveScaled18 balance"
            );
        }
    }
    // #endregion
}
