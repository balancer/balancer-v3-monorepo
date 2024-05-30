// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Proxy } from "@openzeppelin/contracts/proxy/Proxy.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IProtocolFeeCollector } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeCollector.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { StorageSlot } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlot.sol";

import { VaultStateBits, VaultStateLib } from "./lib/VaultStateLib.sol";
import { PoolConfigBits, PoolConfigLib } from "./lib/PoolConfigLib.sol";
import { HooksConfigLib } from "./lib/HooksConfigLib.sol";
import { PackedTokenBalance } from "./lib/PackedTokenBalance.sol";
import { PoolDataLib } from "./lib/PoolDataLib.sol";
import { BufferPackedTokenBalance } from "./lib/BufferPackedBalance.sol";
import { VaultCommon } from "./VaultCommon.sol";

contract Vault is IVaultMain, VaultCommon, Proxy {
    using EnumerableMap for EnumerableMap.IERC20ToBytes32Map;
    using PackedTokenBalance for bytes32;
    using InputHelpers for uint256;
    using FixedPoint for *;
    using ArrayHelpers for uint256[];
    using Address for *;
    using SafeERC20 for IERC20;
    using PoolConfigLib for PoolConfig;
    using HooksConfigLib for HooksConfig;
    using ScalingHelpers for *;
    using VaultStateLib for VaultStateBits;
    using BufferPackedTokenBalance for bytes32;
    using TransientStorageHelpers for *;
    using StorageSlot for *;
    using PoolDataLib for PoolData;

    constructor(IVaultExtension vaultExtension, IAuthorizer authorizer, IProtocolFeeCollector protocolFeeCollector) {
        if (address(vaultExtension.vault()) != address(this)) {
            revert WrongVaultExtensionDeployment();
        }

        if (address(protocolFeeCollector.vault()) != address(this)) {
            revert WrongProtocolFeeCollectorDeployment();
        }

        _vaultExtension = vaultExtension;
        _protocolFeeCollector = protocolFeeCollector;

        _vaultPauseWindowEndTime = IVaultAdmin(address(vaultExtension)).getPauseWindowEndTime();
        _vaultBufferPeriodDuration = IVaultAdmin(address(vaultExtension)).getBufferPeriodDuration();
        _vaultBufferPeriodEndTime = IVaultAdmin(address(vaultExtension)).getBufferPeriodEndTime();

        _authorizer = authorizer;
    }

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /**
     * @dev This modifier is used for functions that temporarily modify the token deltas
     * of the Vault, but expect to revert or settle balances by the end of their execution.
     * It works by ensuring that the balances are properly settled by the time the last
     * operation is executed.
     *
     * This is useful for functions like `lock`, which perform arbitrary external calls:
     * we can keep track of temporary deltas changes, and make sure they are settled by the
     * time the external call is complete.
     */
    modifier transient() {
        bool isUnlockedBefore = _isUnlocked().tload();

        if (isUnlockedBefore == false) {
            _isUnlocked().tstore(true);
        }

        // The caller does everything here and has to settle all outstanding balances
        _;

        if (isUnlockedBefore == false) {
            if (_nonzeroDeltaCount().tload() != 0) {
                revert BalanceNotSettled();
            }

            _isUnlocked().tstore(false);
        }
    }

    /// @inheritdoc IVaultMain
    function unlock(bytes calldata data) external payable transient returns (bytes memory result) {
        // Executes the function call with value to the msg.sender.
        return (msg.sender).functionCallWithValue(data, msg.value);
    }

    /// @inheritdoc IVaultMain
    function settle(IERC20 token) public nonReentrant onlyWhenUnlocked returns (uint256 paid) {
        uint256 reservesBefore = _reservesOf[token];
        _reservesOf[token] = token.balanceOf(address(this));
        paid = _reservesOf[token] - reservesBefore;

        _supplyCredit(token, paid);
    }

    /// @inheritdoc IVaultMain
    function sendTo(IERC20 token, address to, uint256 amount) public nonReentrant onlyWhenUnlocked {
        _takeDebt(token, amount);
        _reservesOf[token] -= amount;

        token.safeTransfer(to, amount);
    }

    /*******************************************************************************
                                    Pool Operations
    *******************************************************************************/

    // The Vault performs all upscaling and downscaling (due to token decimals, rates, etc.), so that the pools
    // don't have to. However, scaling inevitably leads to rounding errors, so we take great care to ensure that
    // any rounding errors favor the Vault. An important invariant of the system is that there is no repeatable
    // path where tokensOut > tokensIn.
    //
    // In general, this means rounding up any values entering the Vault, and rounding down any values leaving
    // the Vault, so that external users either pay a little extra or receive a little less in the case of a
    // rounding error.
    //
    // However, it's not always straightforward to determine the correct rounding direction, given the presence
    // and complexity of intermediate steps. An "amountIn" sounds like it should be rounded up: but only if that
    // is the amount actually being transferred. If instead it is an amount sent to the pool math, where rounding
    // up would result in a *higher* calculated amount out, that would favor the user instead of the Vault. So in
    // that case, amountIn should be rounded down.
    //
    // See comments justifying the rounding direction in each case.
    //
    // TODO: this reasoning applies to Weighted Pool math, and is likely to apply to others as well, but of course
    // it's possible a new pool type might not conform. Duplicate the tests for new pool types (e.g., Stable Math).
    // Also, the final code should ensure that we are not relying entirely on the rounding directions here,
    // but have enough additional layers (e.g., minimum amounts, buffer wei on all transfers) to guarantee safety,
    // even if it turns out these directions are incorrect for a new pool type.

    /*******************************************************************************
                                          Swaps
    *******************************************************************************/

    /// @inheritdoc IVaultMain
    function swap(
        SwapParams memory params
    )
        public
        onlyWhenUnlocked
        withInitializedPool(params.pool)
        returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut)
    {
        _ensureUnpausedAndGetVaultState(params.pool);
        HooksConfig memory hooksConfig = _hooksConfig[params.pool];

        if (params.amountGivenRaw == 0) {
            revert AmountGivenZero();
        }

        if (params.tokenIn == params.tokenOut) {
            revert CannotSwapSameToken();
        }

        // `_loadPoolDataUpdatingBalancesAndYieldFees` is non-reentrant, as it updates storage as well
        // as filling in poolData in memory. Since the swap hooks are reentrant and could do anything, including
        // change these balances, we cannot defer settlement until `_swap`.
        //
        // Sets all fields in `poolData`. Side effects: updates `_poolTokenBalances`, `_aggregateProtocolFeeAmounts`
        // in storage.
        PoolData memory poolData = _loadPoolDataUpdatingBalancesAndYieldFees(params.pool, Rounding.ROUND_DOWN);

        // State is fully populated here, and shall not be modified at a lower level.
        SwapState memory state = _loadSwapState(params, poolData);

        if (hooksConfig.onBeforeSwap(_buildPoolSwapParams(params, state, poolData)) == true) {
            // The call to `onBeforeSwap` could potentially update token rates and balances.
            // We update `poolData.tokenRates`, `poolData.rawBalances` and `poolData.balancesLiveScaled18`
            // to ensure the `onSwap` and `onComputeDynamicSwapFee` are called with the current values.
            poolData.reloadBalancesAndRates(_poolTokenBalances[params.pool], Rounding.ROUND_DOWN);

            // Also update amountGivenScaled18, as it will now be used in the swap, and the rates might have changed.
            state.amountGivenScaled18 = _computeAmountGivenScaled18(state.indexIn, state.indexOut, params, poolData);
        }

        // Note that this must be called *after* the before hook, to guarantee that the swap params are the same
        // as those passed to the main operation.
        // At this point, the static swap fee percentage is loaded in the swap state as the default,
        // to be used unless the pool has a dynamic swap fee.
        (bool dynamicSwapFeeCalculated, uint256 dynamicSwapFee) = hooksConfig.onComputeDynamicSwapFee(
            _buildPoolSwapParams(params, state, poolData)
        );
        if (dynamicSwapFeeCalculated) {
            state.swapFeePercentage = dynamicSwapFee;
        }

        // Non-reentrant call that updates accounting.
        // The following side-effects are important to note:
        // PoolData balancesRaw and balancesLiveScaled18 are adjusted for swap amounts and fees inside of _swap.
        uint256 amountCalculatedScaled18;
        (amountCalculated, amountCalculatedScaled18, amountIn, amountOut) = _swap(params, state, poolData);

        hooksConfig.onAfterSwap(amountCalculatedScaled18, msg.sender, params, state, poolData);
    }

    function _loadSwapState(
        SwapParams memory params,
        PoolData memory poolData
    ) private view returns (SwapState memory state) {
        // Use the storage map only for translating token addresses to indices. Raw balances can be read from poolData.
        EnumerableMap.IERC20ToBytes32Map storage poolBalances = _poolTokenBalances[params.pool];

        // EnumerableMap stores indices *plus one* to use the zero index as a sentinel value for non-existence.
        uint256 indexIn = poolBalances.unchecked_indexOf(params.tokenIn);
        uint256 indexOut = poolBalances.unchecked_indexOf(params.tokenOut);

        // If either are zero, revert because the token wasn't registered to this pool.
        if (indexIn == 0 || indexOut == 0) {
            // We require the pool to be initialized, which means it's also registered.
            // This can only happen if the tokens are not registered.
            revert TokenNotRegistered();
        }

        // Convert to regular 0-based indices now, since we've established the tokens are valid.
        unchecked {
            indexIn -= 1;
            indexOut -= 1;
        }

        state.indexIn = indexIn;
        state.indexOut = indexOut;

        // If the amountGiven is entering the pool math (ExactIn), round down, since a lower apparent amountIn leads
        // to a lower calculated amountOut, favoring the pool.
        state.amountGivenScaled18 = _computeAmountGivenScaled18(indexIn, indexOut, params, poolData);
        state.swapFeePercentage = poolData.poolConfig.staticSwapFeePercentage;
    }

    function _buildPoolSwapParams(
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    ) internal view returns (IBasePool.PoolSwapParams memory) {
        return
            IBasePool.PoolSwapParams({
                kind: params.kind,
                amountGivenScaled18: state.amountGivenScaled18,
                balancesScaled18: poolData.balancesLiveScaled18,
                indexIn: state.indexIn,
                indexOut: state.indexOut,
                router: msg.sender,
                userData: params.userData
            });
    }

    /**
     * @dev Preconditions: decimalScalingFactors and tokenRates in `poolData` must be current.
     * Uses amountGivenRaw and kind from `params`.
     */
    function _computeAmountGivenScaled18(
        uint256 indexIn,
        uint256 indexOut,
        SwapParams memory params,
        PoolData memory poolData
    ) private pure returns (uint256) {
        // If the amountGiven is entering the pool math (ExactIn), round down, since a lower apparent amountIn leads
        // to a lower calculated amountOut, favoring the pool.
        return
            params.kind == SwapKind.EXACT_IN
                ? params.amountGivenRaw.toScaled18ApplyRateRoundDown(
                    poolData.decimalScalingFactors[indexIn],
                    poolData.tokenRates[indexIn]
                )
                : params.amountGivenRaw.toScaled18ApplyRateRoundUp(
                    poolData.decimalScalingFactors[indexOut],
                    poolData.tokenRates[indexOut]
                );
    }

    struct SwapInternalLocals {
        uint256 swapFeeAmountScaled18;
        uint256 swapFeeIndex;
        IERC20 swapFeeToken;
        uint256 balanceInIncrement;
        uint256 balanceOutDecrement;
        uint256 swapFeeAmountRaw;
    }

    /**
     * @dev Main non-reentrant portion of the swap, which calls the pool hook and updates accounting. `vaultSwapParams`
     * are passed to the pool's `onSwap` hook.
     *
     * Preconditions: complete `SwapParams`, `SwapState`, and `PoolData`.
     * Side effects: mutates balancesRaw and balancesLiveScaled18 in `poolData`.
     * Updates `_aggregateProtocolFeeAmounts`, and `_poolTokenBalances` in storage.
     * Emits Swap event.
     */
    function _swap(
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    )
        internal
        nonReentrant
        returns (
            uint256 amountCalculatedRaw,
            uint256 amountCalculatedScaled18,
            uint256 amountInRaw,
            uint256 amountOutRaw
        )
    {
        SwapInternalLocals memory locals;

        // Perform the swap request hook and compute the new balances for 'token in' and 'token out' after the swap
        amountCalculatedScaled18 = IBasePool(params.pool).onSwap(_buildPoolSwapParams(params, state, poolData));

        // Note that balances are kept in memory, and are not fully computed until the `setPoolBalances` below.
        // Intervening code cannot read balances from storage, as they are temporarily out-of-sync here. This function
        // is nonReentrant, to guard against read-only reentrancy issues.

        // Set locals.swapFeeAmountScaled18 based on the amountCalculated.
        if (state.swapFeePercentage > 0) {
            // Swap fee is always a percentage of the amountCalculated. On ExactIn, subtract it from the calculated
            // amountOut. On ExactOut, add it to the calculated amountIn.
            // Round up to avoid losses during precision loss.
            locals.swapFeeAmountScaled18 = amountCalculatedScaled18.mulUp(state.swapFeePercentage);
        }

        // (1) and (2): get raw amounts and check limits
        if (params.kind == SwapKind.EXACT_IN) {
            // Need to update `amountCalculatedScaled18` for the onAfterSwap hook.
            amountCalculatedScaled18 -= locals.swapFeeAmountScaled18;

            // For `ExactIn` the amount calculated is leaving the Vault, so we round down.
            amountCalculatedRaw = amountCalculatedScaled18.toRawUndoRateRoundDown(
                poolData.decimalScalingFactors[state.indexOut],
                poolData.tokenRates[state.indexOut]
            );

            (amountInRaw, amountOutRaw) = (params.amountGivenRaw, amountCalculatedRaw);

            if (amountOutRaw < params.limitRaw) {
                revert SwapLimit(amountOutRaw, params.limitRaw);
            }
        } else {
            amountCalculatedScaled18 += locals.swapFeeAmountScaled18;

            // For `ExactOut` the amount calculated is entering the Vault, so we round up.
            amountCalculatedRaw = amountCalculatedScaled18.toRawUndoRateRoundUp(
                poolData.decimalScalingFactors[state.indexIn],
                poolData.tokenRates[state.indexIn]
            );

            (amountInRaw, amountOutRaw) = (amountCalculatedRaw, params.amountGivenRaw);

            if (amountInRaw > params.limitRaw) {
                revert SwapLimit(amountInRaw, params.limitRaw);
            }
        }

        // 3) Deltas: debit for token in, credit for token out
        _takeDebt(params.tokenIn, amountInRaw);
        _supplyCredit(params.tokenOut, amountOutRaw);

        // 4) Compute and charge protocol and creator fees.
        (locals.swapFeeIndex, locals.swapFeeToken) = params.kind == SwapKind.EXACT_IN
            ? (state.indexOut, params.tokenOut)
            : (state.indexIn, params.tokenIn);

        // Note that protocol fee storage is updated before balance storage, as the final raw balances need to take
        // the fees into account.
        uint256 totalFeesRaw = _computeAndChargeAggregateProtocolSwapFees(
            poolData,
            locals.swapFeeAmountScaled18,
            params.pool,
            locals.swapFeeToken,
            locals.swapFeeIndex
        );

        // 5) Pool balances: raw and live
        // Adjust for raw swap amounts and total fees on the calculated end.
        // So that fees are always subtracted from pool balances:
        // For ExactIn, we increase the tokenIn balance by `amountIn`, and decrease the tokenOut balance by the
        // (`amountOut` + fees).
        // For ExactOut, we increase the tokenInBalance by (`amountIn` - fees), and decrease the tokenOut balance by
        // `amountOut`.
        (locals.balanceInIncrement, locals.balanceOutDecrement) = params.kind == SwapKind.EXACT_IN
            ? (amountInRaw, amountOutRaw + totalFeesRaw)
            : (amountInRaw - totalFeesRaw, amountOutRaw);
        poolData.increaseTokenBalance(state.indexIn, locals.balanceInIncrement);
        poolData.decreaseTokenBalance(state.indexOut, locals.balanceOutDecrement);

        // 6) Store pool balances, raw and live (only index in and out)
        EnumerableMap.IERC20ToBytes32Map storage poolBalances = _poolTokenBalances[params.pool];
        poolBalances.unchecked_setAt(
            state.indexIn,
            PackedTokenBalance.toPackedBalance(
                poolData.balancesRaw[state.indexIn],
                poolData.balancesLiveScaled18[state.indexIn]
            )
        );
        poolBalances.unchecked_setAt(
            state.indexOut,
            PackedTokenBalance.toPackedBalance(
                poolData.balancesRaw[state.indexOut],
                poolData.balancesLiveScaled18[state.indexOut]
            )
        );

        // 7) Off-chain events
        // Since the swapFeeAmountScaled18 (derived from scaling up either the amountGiven or amountCalculated)
        // also contains the rate, undo it when converting to raw.
        locals.swapFeeAmountRaw = locals.swapFeeAmountScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[locals.swapFeeIndex],
            poolData.tokenRates[locals.swapFeeIndex]
        );

        emit Swap(
            params.pool,
            params.tokenIn,
            params.tokenOut,
            amountInRaw,
            amountOutRaw,
            state.swapFeePercentage,
            locals.swapFeeAmountRaw,
            locals.swapFeeToken
        );
    }

    /*******************************************************************************
                                Pool Operations
    *******************************************************************************/

    /// @inheritdoc IVaultMain
    function addLiquidity(
        AddLiquidityParams memory params
    )
        external
        onlyWhenUnlocked
        withInitializedPool(params.pool)
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData)
    {
        // Round balances up when adding liquidity:
        // If proportional, higher balances = higher proportional amountsIn, favoring the pool.
        // If unbalanced, higher balances = lower invariant ratio with fees.
        // bptOut = supply * (ratio - 1), so lower ratio = less bptOut, favoring the pool.

        _ensureUnpausedAndGetVaultState(params.pool);
        HooksConfig memory hooksConfig = _hooksConfig[params.pool];

        // `_loadPoolDataUpdatingBalancesAndYieldFees` is non-reentrant, as it updates storage as well
        // as filling in poolData in memory. Since the add liquidity hooks are reentrant and could do anything,
        // including change these balances, we cannot defer settlement until `_addLiquidity`.
        //
        // Sets all fields in `poolData`. Side effects: updates `_poolTokenBalances`, and
        // `_aggregateProtocolFeeAmounts` in storage.
        PoolData memory poolData = _loadPoolDataUpdatingBalancesAndYieldFees(params.pool, Rounding.ROUND_UP);
        InputHelpers.ensureInputLengthMatch(poolData.tokenConfig.length, params.maxAmountsIn.length);

        // Amounts are entering pool math, so round down.
        // Introducing amountsInScaled18 here and passing it through to _addLiquidity is not ideal,
        // but it avoids the even worse options of mutating amountsIn inside AddLiquidityParams,
        // or cluttering the AddLiquidityParams interface by adding amountsInScaled18.
        uint256[] memory maxAmountsInScaled18 = params.maxAmountsIn.copyToScaled18ApplyRateRoundDownArray(
            poolData.decimalScalingFactors,
            poolData.tokenRates
        );

        if (hooksConfig.onBeforeAddLiquidity(maxAmountsInScaled18, msg.sender, params, poolData)) {
            // The hook might alter the balances, so we need to read them again to ensure that the data is
            // fresh moving forward.
            // We also need to upscale (adding liquidity, so round up) again.
            poolData.reloadBalancesAndRates(_poolTokenBalances[params.pool], Rounding.ROUND_UP);

            // Also update maxAmountsInScaled18, as the rates might have changed.
            maxAmountsInScaled18 = params.maxAmountsIn.copyToScaled18ApplyRateRoundDownArray(
                poolData.decimalScalingFactors,
                poolData.tokenRates
            );
        }

        // The bulk of the work is done here: the corresponding Pool hook is called, and the final balances
        // are computed. This function is non-reentrant, as it performs the accounting updates.
        // Note that poolData is mutated to update the Raw and Live balances, so they are accurate when passed
        // into the AfterAddLiquidity hook.
        // `amountsInScaled18` will be overwritten in the custom case, so we need to pass it back and forth to
        // encapsulate that logic in `_addLiquidity`.
        uint256[] memory amountsInScaled18;
        (amountsIn, amountsInScaled18, bptAmountOut, returnData) = _addLiquidity(
            poolData,
            params,
            maxAmountsInScaled18
        );

        hooksConfig.onAfterAddLiquidity(amountsInScaled18, bptAmountOut, msg.sender, params, poolData);
    }

    /// @dev Avoid "stack too deep" - without polluting the Add/RemoveLiquidity params interface.
    struct LiquidityLocals {
        uint256 numTokens;
        uint256 totalFeesRaw;
        uint256 tokenIndex;
    }

    /**
     * @dev Calls the appropriate pool hook and calculates the required inputs and outputs for the operation
     * considering the given kind, and updates the vault's internal accounting. This includes:
     * - Setting pool balances
     * - Taking debt from the liquidity provider
     * - Minting pool tokens
     * - Emitting events
     *
     * It is non-reentrant, as it performs external calls and updates the vault's state accordingly.
     */
    function _addLiquidity(
        PoolData memory poolData,
        AddLiquidityParams memory params,
        uint256[] memory maxAmountsInScaled18
    )
        internal
        nonReentrant
        returns (
            uint256[] memory amountsInRaw,
            uint256[] memory amountsInScaled18,
            uint256 bptAmountOut,
            bytes memory returnData
        )
    {
        LiquidityLocals memory locals;
        locals.numTokens = poolData.tokenConfig.length;
        uint256[] memory swapFeeAmountsScaled18;

        if (params.kind == AddLiquidityKind.PROPORTIONAL) {
            bptAmountOut = params.minBptAmountOut;
            // Initializes the swapFeeAmountsScaled18 empty array (no swap fees on proportional add liquidity)
            swapFeeAmountsScaled18 = new uint256[](locals.numTokens);

            amountsInScaled18 = BasePoolMath.computeProportionalAmountsIn(
                poolData.balancesLiveScaled18,
                _totalSupply(params.pool),
                bptAmountOut
            );
        } else if (params.kind == AddLiquidityKind.UNBALANCED) {
            poolData.poolConfig.requireUnbalancedLiquidityEnabled();

            amountsInScaled18 = maxAmountsInScaled18;
            (bptAmountOut, swapFeeAmountsScaled18) = BasePoolMath.computeAddLiquidityUnbalanced(
                poolData.balancesLiveScaled18,
                maxAmountsInScaled18,
                _totalSupply(params.pool),
                poolData.poolConfig.staticSwapFeePercentage,
                IBasePool(params.pool).computeInvariant
            );
        } else if (params.kind == AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            poolData.poolConfig.requireUnbalancedLiquidityEnabled();

            bptAmountOut = params.minBptAmountOut;
            locals.tokenIndex = InputHelpers.getSingleInputIndex(maxAmountsInScaled18);

            amountsInScaled18 = maxAmountsInScaled18;
            (amountsInScaled18[locals.tokenIndex], swapFeeAmountsScaled18) = BasePoolMath
                .computeAddLiquiditySingleTokenExactOut(
                    poolData.balancesLiveScaled18,
                    locals.tokenIndex,
                    bptAmountOut,
                    _totalSupply(params.pool),
                    poolData.poolConfig.staticSwapFeePercentage,
                    IBasePool(params.pool).computeBalance
                );
        } else if (params.kind == AddLiquidityKind.CUSTOM) {
            poolData.poolConfig.requireAddCustomLiquidityEnabled();

            (amountsInScaled18, bptAmountOut, swapFeeAmountsScaled18, returnData) = IPoolLiquidity(params.pool)
                .onAddLiquidityCustom(
                    msg.sender,
                    maxAmountsInScaled18,
                    params.minBptAmountOut,
                    poolData.balancesLiveScaled18,
                    params.userData
                );
        } else {
            revert InvalidAddLiquidityKind();
        }

        // At this point we have the calculated BPT amount.
        if (bptAmountOut < params.minBptAmountOut) {
            revert BptAmountOutBelowMin(bptAmountOut, params.minBptAmountOut);
        }

        amountsInRaw = new uint256[](locals.numTokens);

        for (uint256 i = 0; i < locals.numTokens; ++i) {
            // 1) Calculate raw amount in.
            // amountsInRaw are amounts actually entering the Pool, so we round up.
            // Do not mutate in place yet, as we need them scaled for the `onAfterAddLiquidity` hook
            uint256 amountInRaw = amountsInScaled18[i].toRawUndoRateRoundUp(
                poolData.decimalScalingFactors[i],
                poolData.tokenRates[i]
            );
            amountsInRaw[i] = amountInRaw;

            {
                // stack-too-deep (forge)
                IERC20 token = poolData.tokenConfig[i].token;

                // 2) Check limits for raw amounts
                if (amountInRaw > params.maxAmountsIn[i]) {
                    revert AmountInAboveMax(token, amountInRaw, params.maxAmountsIn[i]);
                }

                // 3) Deltas: Debit of token[i] for amountInRaw
                _takeDebt(token, amountInRaw);

                // 4) Compute and charge protocol and creator fees.
                locals.totalFeesRaw = _computeAndChargeAggregateProtocolSwapFees(
                    poolData,
                    swapFeeAmountsScaled18[i],
                    params.pool,
                    token,
                    i
                );
            }

            // 5) Pool balances: raw and live
            // We need regular balances to complete the accounting, and the upscaled balances
            // to use in the `after` hook later on.

            // A pool's token balance increases by amounts in after adding liquidity, minus fees.
            uint256 amountToIncreaseRaw = amountInRaw - locals.totalFeesRaw;

            poolData.increaseTokenBalance(i, amountToIncreaseRaw);
        }

        // 6) Store pool balances, raw and live
        _writePoolBalancesToStorage(params.pool, poolData);

        // 7) BPT supply adjustment
        // When adding liquidity, we must mint tokens concurrently with updating pool balances,
        // as the pool's math relies on totalSupply.
        _mint(address(params.pool), params.to, bptAmountOut);

        // 8) Off-chain events
        emit PoolBalanceChanged(params.pool, params.to, amountsInRaw.unsafeCastToInt256(true));
    }

    /// @inheritdoc IVaultMain
    function removeLiquidity(
        RemoveLiquidityParams memory params
    )
        external
        onlyWhenUnlocked
        withInitializedPool(params.pool)
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData)
    {
        // Round down when removing liquidity:
        // If proportional, lower balances = lower proportional amountsOut, favoring the pool.
        // If unbalanced, lower balances = lower invariant ratio without fees.
        // bptIn = supply * (1 - ratio), so lower ratio = more bptIn, favoring the pool.

        VaultState memory vaultState = _ensureUnpausedAndGetVaultState(params.pool);
        HooksConfig memory hooksConfig = _hooksConfig[params.pool];

        // `_loadPoolDataUpdatingBalancesAndYieldFees` is non-reentrant, as it updates storage as well
        // as filling in poolData in memory. Since the swap hooks are reentrant and could do anything, including
        // change these balances, we cannot defer settlement until `_removeLiquidity`.
        //
        // Sets all fields in `poolData`. Side effects: updates `_poolTokenBalances` and
        // `_aggregateProtocolFeeAmounts in storage.
        PoolData memory poolData = _loadPoolDataUpdatingBalancesAndYieldFees(params.pool, Rounding.ROUND_DOWN);
        InputHelpers.ensureInputLengthMatch(poolData.tokenConfig.length, params.minAmountsOut.length);

        // Amounts are entering pool math; higher amounts would burn more BPT, so round up to favor the pool.
        // Do not mutate minAmountsOut, so that we can directly compare the raw limits later, without potentially
        // losing precision by scaling up and then down.
        uint256[] memory minAmountsOutScaled18 = params.minAmountsOut.copyToScaled18ApplyRateRoundUpArray(
            poolData.decimalScalingFactors,
            poolData.tokenRates
        );

        if (hooksConfig.onBeforeRemoveLiquidity(minAmountsOutScaled18, msg.sender, params, poolData) == true) {
            // The hook might alter the balances, so we need to read them again to ensure that the data is
            // fresh moving forward.
            // We also need to upscale (removing liquidity, so round down) again.
            poolData.reloadBalancesAndRates(_poolTokenBalances[params.pool], Rounding.ROUND_DOWN);

            // Also update minAmountsOutScaled18, as the rates might have changed.
            minAmountsOutScaled18 = params.minAmountsOut.copyToScaled18ApplyRateRoundUpArray(
                poolData.decimalScalingFactors,
                poolData.tokenRates
            );
        }

        // The bulk of the work is done here: the corresponding Pool hook is called, and the final balances
        // are computed. This function is non-reentrant, as it performs the accounting updates.
        // Note that poolData is mutated to update the Raw and Live balances, so they are accurate when passed
        // into the AfterRemoveLiquidity hook.
        uint256[] memory amountsOutScaled18;
        (bptAmountIn, amountsOut, amountsOutScaled18, returnData) = _removeLiquidity(
            poolData,
            params,
            minAmountsOutScaled18,
            vaultState
        );

        hooksConfig.onAfterRemoveLiquidity(amountsOutScaled18, bptAmountIn, msg.sender, params, poolData);
    }

    /**
     * @dev Calls the appropriate pool hook and calculates the required inputs and outputs for the operation
     * considering the given kind, and updates the vault's internal accounting. This includes:
     * - Setting pool balances
     * - Supplying credit to the liquidity provider
     * - Burning pool tokens
     * - Emitting events
     *
     * It is non-reentrant, as it performs external calls and updates the vault's state accordingly.
     */
    function _removeLiquidity(
        PoolData memory poolData,
        RemoveLiquidityParams memory params,
        uint256[] memory minAmountsOutScaled18,
        VaultState memory vaultState
    )
        internal
        nonReentrant
        returns (
            uint256 bptAmountIn,
            uint256[] memory amountsOutRaw,
            uint256[] memory amountsOutScaled18,
            bytes memory returnData
        )
    {
        LiquidityLocals memory locals;
        locals.numTokens = poolData.tokenConfig.length;
        uint256[] memory swapFeeAmountsScaled18;

        if (params.kind == RemoveLiquidityKind.PROPORTIONAL) {
            bptAmountIn = params.maxBptAmountIn;
            swapFeeAmountsScaled18 = new uint256[](locals.numTokens);
            amountsOutScaled18 = BasePoolMath.computeProportionalAmountsOut(
                poolData.balancesLiveScaled18,
                _totalSupply(params.pool),
                bptAmountIn
            );
        } else if (params.kind == RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN) {
            poolData.poolConfig.requireUnbalancedLiquidityEnabled();
            bptAmountIn = params.maxBptAmountIn;
            amountsOutScaled18 = minAmountsOutScaled18;
            locals.tokenIndex = InputHelpers.getSingleInputIndex(params.minAmountsOut);

            (amountsOutScaled18[locals.tokenIndex], swapFeeAmountsScaled18) = BasePoolMath
                .computeRemoveLiquiditySingleTokenExactIn(
                    poolData.balancesLiveScaled18,
                    locals.tokenIndex,
                    bptAmountIn,
                    _totalSupply(params.pool),
                    poolData.poolConfig.staticSwapFeePercentage,
                    IBasePool(params.pool).computeBalance
                );
        } else if (params.kind == RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            poolData.poolConfig.requireUnbalancedLiquidityEnabled();
            amountsOutScaled18 = minAmountsOutScaled18;
            locals.tokenIndex = InputHelpers.getSingleInputIndex(params.minAmountsOut);

            (bptAmountIn, swapFeeAmountsScaled18) = BasePoolMath.computeRemoveLiquiditySingleTokenExactOut(
                poolData.balancesLiveScaled18,
                locals.tokenIndex,
                amountsOutScaled18[locals.tokenIndex],
                _totalSupply(params.pool),
                poolData.poolConfig.staticSwapFeePercentage,
                IBasePool(params.pool).computeInvariant
            );
        } else if (params.kind == RemoveLiquidityKind.CUSTOM) {
            poolData.poolConfig.requireRemoveCustomLiquidityEnabled();
            (bptAmountIn, amountsOutScaled18, swapFeeAmountsScaled18, returnData) = IPoolLiquidity(params.pool)
                .onRemoveLiquidityCustom(
                    msg.sender,
                    params.maxBptAmountIn,
                    minAmountsOutScaled18,
                    poolData.balancesLiveScaled18,
                    params.userData
                );
        } else {
            revert InvalidRemoveLiquidityKind();
        }

        if (bptAmountIn > params.maxBptAmountIn) {
            revert BptAmountInAboveMax(bptAmountIn, params.maxBptAmountIn);
        }

        amountsOutRaw = new uint256[](locals.numTokens);

        for (uint256 i = 0; i < locals.numTokens; ++i) {
            // 1) Calculate raw amount out.
            // amountsOut are amounts exiting the Pool, so we round down.
            // Do not mutate in place yet, as we need them scaled for the `onAfterRemoveLiquidity` hook
            uint256 amountOutRaw = amountsOutScaled18[i].toRawUndoRateRoundDown(
                poolData.decimalScalingFactors[i],
                poolData.tokenRates[i]
            );
            amountsOutRaw[i] = amountOutRaw;

            {
                // stack-too-deep
                IERC20 token = poolData.tokenConfig[i].token;
                // 2) Check limits for raw amounts
                if (amountOutRaw < params.minAmountsOut[i]) {
                    revert AmountOutBelowMin(token, amountOutRaw, params.minAmountsOut[i]);
                }

                // 3) Deltas: Credit token[i] for amountOutRaw
                _supplyCredit(token, amountOutRaw);

                // 4) Compute and charge protocol and creator fees.
                locals.totalFeesRaw = _computeAndChargeAggregateProtocolSwapFees(
                    poolData,
                    swapFeeAmountsScaled18[i],
                    params.pool,
                    token,
                    i
                );
            }

            // 5) Pool balances: raw and live
            // We need regular balances to complete the accounting, and the upscaled balances
            // to use in the `after` hook later on.

            // A Pool's token balance always decreases after an exit
            // (potentially by 0). Also adjust by protocol and pool creator fees.
            uint256 amountToDecreaseRaw = amountOutRaw + locals.totalFeesRaw;

            poolData.decreaseTokenBalance(i, amountToDecreaseRaw);
        }

        // 6) Store pool balances, raw and live
        _writePoolBalancesToStorage(params.pool, poolData);

        // 7) BPT supply adjustment
        _spendAllowance(address(params.pool), params.from, msg.sender, bptAmountIn);

        if (!vaultState.isQueryDisabled && EVMCallModeHelpers.isStaticCall()) {
            // Increase `from` balance to ensure the burn function succeeds.
            _queryModeBalanceIncrease(params.pool, params.from, bptAmountIn);
        }
        // When removing liquidity, we must burn tokens concurrently with updating pool balances,
        // as the pool's math relies on totalSupply.
        // Burning will be reverted if it results in a total supply less than the _MINIMUM_TOTAL_SUPPLY.
        _burn(address(params.pool), params.from, bptAmountIn);

        // 8) Off-chain events
        emit PoolBalanceChanged(
            params.pool,
            params.from,
            // We can unsafely cast to int256 because balances are stored as uint128 (see PackedTokenBalance).
            amountsOutRaw.unsafeCastToInt256(false)
        );
    }

    /**
     * @dev Preconditions: poolConfig, decimalScalingFactors, tokenRates in `poolData`.
     * Side effects: updates `_aggregateProtocolFeeAmounts` storage.
     * Note that this computes the aggregate total of the protocol fees and stores it, without emitting any events.
     * Splitting the fees and event emission occur during fee collection.
     * Should only be called in a non-reentrant context.
     *
     * @return totalFeesRaw Sum of protocol and pool creator fees raw
     */
    function _computeAndChargeAggregateProtocolSwapFees(
        PoolData memory poolData,
        uint256 swapFeeAmountScaled18,
        address pool,
        IERC20 token,
        uint256 index
    ) internal returns (uint256 totalFeesRaw) {
        // If swapFeeAmount equals zero no need to charge anything
        if (
            swapFeeAmountScaled18 > 0 &&
            poolData.poolConfig.aggregateProtocolSwapFeePercentage > 0 &&
            poolData.poolConfig.isPoolInRecoveryMode == false
        ) {
            uint256 aggregateSwapFeeAmountScaled18 = swapFeeAmountScaled18.mulUp(
                poolData.poolConfig.aggregateProtocolSwapFeePercentage
            );

            // Ensure we can never charge more than the total swap fee.
            if (aggregateSwapFeeAmountScaled18 > swapFeeAmountScaled18) {
                revert ProtocolFeesExceedTotalCollected();
            }

            totalFeesRaw = aggregateSwapFeeAmountScaled18.toRawUndoRateRoundDown(
                poolData.decimalScalingFactors[index],
                poolData.tokenRates[index]
            );

            // Both Swap and Yield fees are stored together in a PackedTokenBalance.
            // We have designated "Raw" the derived half for Swap fee storage.
            bytes32 currentPackedBalance = _aggregateProtocolFeeAmounts[pool][token];
            _aggregateProtocolFeeAmounts[pool][token] = currentPackedBalance.setBalanceRaw(
                currentPackedBalance.getBalanceRaw() + totalFeesRaw
            );
        }
    }

    /// @inheritdoc IVaultMain
    function getProtocolFeeCollector() external view returns (IProtocolFeeCollector) {
        return _protocolFeeCollector;
    }

    /*******************************************************************************
                             Yield-bearing token buffers
    *******************************************************************************/

    /// @inheritdoc IVaultMain
    function erc4626BufferWrapOrUnwrap(
        BufferWrapOrUnwrapParams memory params
    )
        public
        onlyWhenUnlocked
        whenVaultBuffersAreNotPaused
        nonReentrant
        returns (uint256 amountCalculatedRaw, uint256 amountInRaw, uint256 amountOutRaw)
    {
        IERC20 underlyingToken = IERC20(params.wrappedToken.asset());

        address bufferAsset = _bufferAssets[IERC20(params.wrappedToken)];

        if (bufferAsset != address(0) && bufferAsset != address(underlyingToken)) {
            // Asset was changed since the first addLiquidityToBuffer call
            revert WrongWrappedTokenAsset(address(params.wrappedToken));
        }

        if (params.amountGivenRaw < _MINIMUM_WRAP_AMOUNT) {
            // If amount given is too small, rounding issues can be introduced that favors the user and can drain
            // the buffer. _MINIMUM_WRAP_AMOUNT prevents it. Most tokens have protections against it already, this
            // is just an extra layer of security.
            revert WrapAmountTooSmall(address(params.wrappedToken));
        }

        if (params.direction == WrappingDirection.UNWRAP) {
            (amountCalculatedRaw, amountInRaw, amountOutRaw) = _unwrapWithBuffer(
                params.kind,
                underlyingToken,
                params.wrappedToken,
                params.amountGivenRaw
            );
            emit Unwrap(params.wrappedToken, underlyingToken, amountInRaw, amountOutRaw);
        } else {
            (amountCalculatedRaw, amountInRaw, amountOutRaw) = _wrapWithBuffer(
                params.kind,
                underlyingToken,
                params.wrappedToken,
                params.amountGivenRaw
            );
            emit Wrap(underlyingToken, params.wrappedToken, amountInRaw, amountOutRaw);
        }

        if (params.kind == SwapKind.EXACT_IN && amountOutRaw < params.limitRaw) {
            revert SwapLimit(amountOutRaw, params.limitRaw);
        }

        if (params.kind == SwapKind.EXACT_OUT && amountInRaw > params.limitRaw) {
            revert SwapLimit(amountInRaw, params.limitRaw);
        }
    }

    /**
     * @dev If the buffer has enough liquidity, it uses the wrapped token buffer to perform the wrap operation without
     * any external calls. If not, it wraps the assets needed to fulfill the trade + the surplus of assets in the
     * buffer, so that the buffer is rebalanced at the end of the operation.
     *
     * Updates `_reservesOf` and token deltas in storage.
     */
    function _wrapWithBuffer(
        SwapKind kind,
        IERC20 underlyingToken,
        IERC4626 wrappedToken,
        uint256 amountGiven
    ) private returns (uint256 amountCalculated, uint256 amountInUnderlying, uint256 amountOutWrapped) {
        bytes32 bufferBalances = _bufferTokenBalances[IERC20(wrappedToken)];

        if (kind == SwapKind.EXACT_IN) {
            // EXACT_IN wrap, so AmountGiven is underlying amount
            amountCalculated = wrappedToken.convertToShares(amountGiven);
            (amountInUnderlying, amountOutWrapped) = (amountGiven, amountCalculated);
        } else {
            // EXACT_OUT wrap, so AmountGiven is wrapped amount
            amountCalculated = wrappedToken.convertToAssets(amountGiven);
            (amountInUnderlying, amountOutWrapped) = (amountCalculated, amountGiven);
        }

        // Checking isStaticCall first, so we only parse _vaultState in static calls
        if (EVMCallModeHelpers.isStaticCall() == true && _vaultState.toVaultState().isQueryDisabled == false) {
            // Uses the most accurate calculation so that a query matches the actual operation
            if (kind == SwapKind.EXACT_IN) {
                amountCalculated = wrappedToken.previewDeposit(amountGiven);
                (amountInUnderlying, amountOutWrapped) = (amountGiven, amountCalculated);
            } else {
                amountCalculated = wrappedToken.previewMint(amountGiven);
                (amountInUnderlying, amountOutWrapped) = (amountCalculated, amountGiven);
            }
            _takeDebt(underlyingToken, amountInUnderlying);
            _supplyCredit(wrappedToken, amountOutWrapped);
            return (amountCalculated, amountInUnderlying, amountOutWrapped);
        }

        if (bufferBalances.getBalanceDerived() > amountOutWrapped) {
            // The buffer has enough liquidity to facilitate the wrap without making an external call.

            bufferBalances = PackedTokenBalance.toPackedBalance(
                bufferBalances.getBalanceRaw() + amountInUnderlying,
                bufferBalances.getBalanceDerived() - amountOutWrapped
            );
            _bufferTokenBalances[IERC20(wrappedToken)] = bufferBalances;
        } else {
            // The buffer does not have enough liquidity to facilitate the wrap without making an external call.
            // We wrap the user's tokens via an external call and additionally rebalance the buffer if it has a
            // surplus of underlying tokens.
            uint256 calculatedUnderlyingDelta;
            uint256 calculatedWrappedDelta;

            // Gets the amount of underlying to wrap in order to rebalance the buffer
            uint256 bufferUnderlyingSurplus = _getBufferUnderlyingSurplus(bufferBalances, wrappedToken);

            if (kind == SwapKind.EXACT_IN) {
                // The amount of underlying tokens to deposit is the necessary amount to fulfill the trade
                // (amountInUnderlying), plus the amount needed to leave the buffer rebalanced 50/50 at the end
                // (bufferUnderlyingSurplus)
                calculatedUnderlyingDelta = amountInUnderlying + bufferUnderlyingSurplus;

                underlyingToken.forceApprove(address(wrappedToken), calculatedUnderlyingDelta);
                // EXACT_IN requires the exact amount of underlying tokens to be deposited, so deposit is called
                wrappedToken.deposit(calculatedUnderlyingDelta, address(this));
            } else {
                if (bufferUnderlyingSurplus > 0) {
                    calculatedWrappedDelta = amountOutWrapped + wrappedToken.convertToShares(bufferUnderlyingSurplus);
                } else {
                    calculatedWrappedDelta = amountOutWrapped;
                }
                // Add convert error because mint can consume a different amount of tokens than we anticipated with
                // convert
                underlyingToken.forceApprove(
                    address(wrappedToken),
                    _addConvertError(amountInUnderlying + bufferUnderlyingSurplus)
                );

                // EXACT_OUT requires the exact amount of wrapped tokens to be returned, so mint is called
                wrappedToken.mint(calculatedWrappedDelta, address(this));

                // Remove approval, in case mint consumed less tokens than we approved, due to convert error
                underlyingToken.forceApprove(address(wrappedToken), 0);
            }

            (uint256 vaultUnderlyingDelta, uint256 vaultWrappedDelta) = _updateReservesAfterWrapping(
                underlyingToken,
                IERC20(wrappedToken)
            );

            _checkWrapOrUnwrapResults(
                wrappedToken,
                amountInUnderlying,
                bufferUnderlyingSurplus,
                vaultUnderlyingDelta,
                amountOutWrapped,
                0,
                vaultWrappedDelta
            );

            // Only updates buffer balances if buffer has a surplus of underlying tokens
            if (bufferUnderlyingSurplus > 0) {
                // If buffer has an underlying surplus, it wraps the surplus + amountIn, so the final amountIn needs
                // to discount that
                amountInUnderlying = vaultUnderlyingDelta - bufferUnderlyingSurplus;
                // Since bufferUnderlyingSurplus was wrapped, the final amountOut needs to discount the wrapped amount
                // that will stay in the buffer
                amountOutWrapped = vaultWrappedDelta - wrappedToken.convertToShares(bufferUnderlyingSurplus);

                // In a wrap operation, the underlying balance of the buffer will decrease and the wrapped balance will
                // increase. To decrease underlying balance, we get the delta amount that was deposited
                // (vaultUnderlyingDelta) and discounts the amount needed in the wrapping operation
                // (amountInUnderlying). Same logic applies to wrapped balances.
                bufferBalances = PackedTokenBalance.toPackedBalance(
                    bufferBalances.getBalanceRaw() - (vaultUnderlyingDelta - amountInUnderlying),
                    bufferBalances.getBalanceDerived() + (vaultWrappedDelta - amountOutWrapped)
                );
                _bufferTokenBalances[IERC20(wrappedToken)] = bufferBalances;
            } else {
                amountInUnderlying = vaultUnderlyingDelta;
                amountOutWrapped = vaultWrappedDelta;
            }
        }

        _takeDebt(underlyingToken, amountInUnderlying);
        _supplyCredit(wrappedToken, amountOutWrapped);
    }

    /**
     * @dev If the buffer has enough liquidity, it uses the wrapped token buffer to perform the unwrap operation
     * without any external calls. If not, it unwraps the assets needed to fulfill the trade + the surplus of assets
     * in the buffer, so that the buffer is rebalanced at the end of the operation.
     *
     * Updates `_reservesOf` and token deltas in storage.
     */
    function _unwrapWithBuffer(
        SwapKind kind,
        IERC20 underlyingToken,
        IERC4626 wrappedToken,
        uint256 amountGiven
    ) private returns (uint256 amountCalculated, uint256 amountInWrapped, uint256 amountOutUnderlying) {
        bytes32 bufferBalances = _bufferTokenBalances[IERC20(wrappedToken)];

        if (kind == SwapKind.EXACT_IN) {
            // EXACT_IN unwrap, so AmountGiven is wrapped amount
            amountCalculated = wrappedToken.convertToAssets(amountGiven);
            (amountOutUnderlying, amountInWrapped) = (amountCalculated, amountGiven);
        } else {
            // EXACT_OUT unwrap, so AmountGiven is underlying amount
            amountCalculated = wrappedToken.convertToShares(amountGiven);
            (amountOutUnderlying, amountInWrapped) = (amountGiven, amountCalculated);
        }

        // Checking isStaticCall first, so we only parse _vaultState in static calls
        if (EVMCallModeHelpers.isStaticCall() == true && _vaultState.toVaultState().isQueryDisabled == false) {
            // Uses the most accurate calculation so that a query matches the actual operation
            if (kind == SwapKind.EXACT_IN) {
                amountCalculated = wrappedToken.previewRedeem(amountGiven);
                (amountOutUnderlying, amountInWrapped) = (amountCalculated, amountGiven);
            } else {
                amountCalculated = wrappedToken.previewWithdraw(amountGiven);
                (amountOutUnderlying, amountInWrapped) = (amountGiven, amountCalculated);
            }
            _takeDebt(wrappedToken, amountInWrapped);
            _supplyCredit(underlyingToken, amountOutUnderlying);
            return (amountCalculated, amountInWrapped, amountOutUnderlying);
        }

        if (bufferBalances.getBalanceRaw() > amountOutUnderlying) {
            // the buffer has enough liquidity to facilitate the wrap without making an external call.
            bufferBalances = PackedTokenBalance.toPackedBalance(
                bufferBalances.getBalanceRaw() - amountOutUnderlying,
                bufferBalances.getBalanceDerived() + amountInWrapped
            );
            _bufferTokenBalances[IERC20(wrappedToken)] = bufferBalances;
        } else {
            // The buffer does not have enough liquidity to facilitate the unwrap without making an external call.
            // We unwrap the user's tokens via an external call and additionally rebalance the buffer if it has a
            // surplus of underlying tokens.

            // Gets the amount of wrapped tokens to unwrap in order to rebalance the buffer
            uint256 bufferWrappedSurplus = _getBufferWrappedSurplus(bufferBalances, wrappedToken);

            if (kind == SwapKind.EXACT_IN) {
                // EXACT_IN requires the exact amount of wrapped tokens to be unwrapped, so redeem is called
                // The amount of wrapped tokens to redeem is the necessary amount to fulfill the trade
                // (amountInWrapped), plus the amount needed to leave the buffer rebalanced 50/50 at the end
                // (bufferWrappedSurplus)
                wrappedToken.redeem(amountInWrapped + bufferWrappedSurplus, address(this), address(this));
            } else {
                // EXACT_OUT requires the exact amount of underlying tokens to be returned, so withdraw is called.
                // The amount of underlying tokens to withdraw is the necessary amount to fulfill the trade
                // (amountOutUnderlying), plus the amount needed to leave the buffer rebalanced 50/50 at the end
                // (bufferUnderlyingSurplus).
                if (bufferWrappedSurplus > 0) {
                    wrappedToken.withdraw(
                        amountOutUnderlying + wrappedToken.convertToAssets(bufferWrappedSurplus),
                        address(this),
                        address(this)
                    );
                } else {
                    wrappedToken.withdraw(amountOutUnderlying, address(this), address(this));
                }
            }

            (uint256 vaultUnderlyingDelta, uint256 vaultWrappedDelta) = _updateReservesAfterWrapping(
                underlyingToken,
                IERC20(wrappedToken)
            );

            _checkWrapOrUnwrapResults(
                wrappedToken,
                amountOutUnderlying,
                0,
                vaultUnderlyingDelta,
                amountInWrapped,
                bufferWrappedSurplus,
                vaultWrappedDelta
            );

            // Only updates buffer balances if buffer has a surplus of wrapped tokens
            if (bufferWrappedSurplus > 0) {
                // If buffer has a wrapped surplus, it unwraps surplus + amountIn, so the final amountIn needs to
                // discount that
                amountInWrapped = vaultWrappedDelta - bufferWrappedSurplus;
                // Since bufferWrappedSurplus was unwrapped, the final amountOut needs to discount the underlying
                // amount that will stay in the buffer
                amountOutUnderlying = vaultUnderlyingDelta - wrappedToken.convertToAssets(bufferWrappedSurplus);

                // In an unwrap operation, the underlying balance of the buffer will increase and the wrapped balance
                // will decrease. To increase the underlying balance, we get the delta amount that was withdrawn
                // (vaultUnderlyingDelta) and discount the amount expected in the unwrapping operation
                // (amountOutUnderlying). The same logic applies to wrapped balances.
                bufferBalances = PackedTokenBalance.toPackedBalance(
                    bufferBalances.getBalanceRaw() + (vaultUnderlyingDelta - amountOutUnderlying),
                    bufferBalances.getBalanceDerived() - (vaultWrappedDelta - amountInWrapped)
                );
                _bufferTokenBalances[IERC20(wrappedToken)] = bufferBalances;
            } else {
                amountOutUnderlying = vaultUnderlyingDelta;
                amountInWrapped = vaultWrappedDelta;
            }
        }

        _takeDebt(wrappedToken, amountInWrapped);
        _supplyCredit(underlyingToken, amountOutUnderlying);
    }

    /**
     * @dev Underlying surplus is the amount of underlying that need to be wrapped for the buffer to be rebalanced.
     * For instance, consider the following scenario:
     * - buffer balances: 2 wrapped and 10 underlying
     * - wrapped rate: 2
     * - normalized buffer balances: 4 wrapped as underlying (2 wrapped * rate) and 10 underlying
     * - surplus of underlying = (10 - 4) / 2 = 3 underlying
     * We need to wrap 3 underlying tokens to consider the buffer rebalanced.
     * - 3 underlying = 1.5 wrapped
     * - final balances: 3.5 wrapped (2 existing + 1.5 new) and 7 underlying (10 existing - 3)
     */
    function _getBufferUnderlyingSurplus(bytes32 bufferBalance, IERC4626 wrappedToken) internal view returns (uint256) {
        uint256 underlyingBalance = bufferBalance.getBalanceRaw();

        uint256 wrappedBalanceAsUnderlying = 0;
        if (bufferBalance.getBalanceDerived() > 0) {
            wrappedBalanceAsUnderlying = wrappedToken.convertToAssets(bufferBalance.getBalanceDerived());
        }

        return
            underlyingBalance > wrappedBalanceAsUnderlying ? (underlyingBalance - wrappedBalanceAsUnderlying) / 2 : 0;
    }

    /**
     * @dev Wrapped surplus is the amount of wrapped tokens that need to be unwrapped for the buffer to be rebalanced.
     * For instance, consider the following scenario:
     * - buffer balances: 10 wrapped and 4 underlying
     * - wrapped rate: 2
     * - normalized buffer balances: 10 wrapped and 2 underlying as wrapped (2 underlying / rate)
     * - surplus of wrapped = (10 - 2) / 2 = 4 wrapped
     * We need to unwrap 4 wrapped tokens to consider the buffer rebalanced.
     * - 4 wrapped = 8 underlying
     * - final balances: 6 wrapped (10 existing - 4) and 12 underlying (4 existing + 8 new)
     */
    function _getBufferWrappedSurplus(bytes32 bufferBalance, IERC4626 wrappedToken) internal view returns (uint256) {
        uint256 wrappedBalance = bufferBalance.getBalanceDerived();

        uint256 underlyingBalanceAsWrapped = 0;
        if (bufferBalance.getBalanceRaw() > 0) {
            underlyingBalanceAsWrapped = wrappedToken.convertToShares(bufferBalance.getBalanceRaw());
        }

        return wrappedBalance > underlyingBalanceAsWrapped ? (wrappedBalance - underlyingBalanceAsWrapped) / 2 : 0;
    }

    /**
     * @dev Updates reserves for underlying and wrapped tokens after wrap/unwrap operation:
     * - updates `_reservesOf`
     * - returns the delta underlying and wrapped tokens that were deposited/withdrawn from vault reserves
     */
    function _updateReservesAfterWrapping(
        IERC20 underlyingToken,
        IERC20 wrappedToken
    ) internal returns (uint256 vaultUnderlyingDelta, uint256 vaultWrappedDelta) {
        uint256 vaultUnderlyingBefore = _reservesOf[underlyingToken];
        uint256 vaultUnderlyingAfter = underlyingToken.balanceOf(address(this));
        _reservesOf[underlyingToken] = vaultUnderlyingAfter;

        uint256 vaultWrappedBefore = _reservesOf[IERC20(wrappedToken)];
        uint256 vaultWrappedAfter = wrappedToken.balanceOf(address(this));
        _reservesOf[wrappedToken] = vaultWrappedAfter;

        if (vaultUnderlyingBefore > vaultUnderlyingAfter) {
            // Wrap
            // Since deposit takes underlying tokens from the vault, the actual underlying tokens deposited is
            // underlyingBefore - underlyingAfter
            vaultUnderlyingDelta = vaultUnderlyingBefore - vaultUnderlyingAfter;
            // Since deposit puts wrapped tokens into the vault, the actual wrapped minted is
            // wrappedAfter - wrappedBefore
            vaultWrappedDelta = vaultWrappedAfter - vaultWrappedBefore;
        } else {
            // Unwrap
            // Since withdraw puts underlying tokens into the vault, the actual underlying token amount withdrawn is
            // assetsAfter - assetsBefore
            vaultUnderlyingDelta = vaultUnderlyingAfter - vaultUnderlyingBefore;
            // Since withdraw takes wrapped tokens from the vault, the actual wrapped token amount burned is
            // wrappedBefore - wrappedAfter
            vaultWrappedDelta = vaultWrappedBefore - vaultWrappedAfter;
        }
    }

    /**
     * @dev Check if vault deltas after wrap or unwrap operation match the expected amount calculated by
     * convertToAssets/convertToShares, with an error tolerance of _MAX_CONVERT_ERROR
     */
    function _checkWrapOrUnwrapResults(
        IERC4626 wrappedToken,
        uint256 wrapUnwrapUnderlyingExpected,
        uint256 bufferUnderlyingSurplus,
        uint256 vaultUnderlyingDelta,
        uint256 wrapUnwrapWrappedExpected,
        uint256 bufferWrappedSurplus,
        uint256 vaultWrappedDelta
    ) private view {
        uint256 expectedUnderlyingDelta;
        uint256 expectedWrappedDelta;
        if (bufferUnderlyingSurplus > 0) {
            // If buffer has a surplus of underlying, the expected underlying delta is the underlying amountIn from the
            // user (wrapUnwrapUnderlyingExpected) + bufferUnderlyingSurplus. This value left vault's reserves because
            // it was wrapped
            expectedUnderlyingDelta = wrapUnwrapUnderlyingExpected + bufferUnderlyingSurplus;
            // If buffer has a surplus of underlying, the expected wrapped delta is the wrapped amountOut to the
            // user (wrapUnwrapWrappedExpected) + converted bufferUnderlyingSurplus. This value was added to vault's
            // reserves because underlying was wrapped
            expectedWrappedDelta = wrapUnwrapWrappedExpected + wrappedToken.convertToShares(bufferUnderlyingSurplus);
        } else if (bufferWrappedSurplus > 0) {
            // If buffer has a surplus of wrapped, the expected wrapped delta is the wrapped amountIn from the
            // user (wrapUnwrapWrappedExpected) + bufferWrappedSurplus. This value left vault's reserves because
            // it was unwrapped
            expectedWrappedDelta = wrapUnwrapWrappedExpected + bufferWrappedSurplus;
            // If buffer has a surplus of wrapped, the expected underlying delta is the underlying amountOut to the
            // user (wrapUnwrapUnderlyingExpected) + converted bufferWrappedSurplus. This value was added to vault's
            // reserves because wrapped was redeemed
            expectedUnderlyingDelta = wrapUnwrapUnderlyingExpected + wrappedToken.convertToAssets(bufferWrappedSurplus);
        } else {
            // If no surplus, the expected delta is the amountsIn and amountsOut (perfectly balanced buffer or
            // operation was not in favor of rebalance)
            expectedUnderlyingDelta = wrapUnwrapUnderlyingExpected;
            expectedWrappedDelta = wrapUnwrapWrappedExpected;
        }

        if (
            (vaultUnderlyingDelta < expectedUnderlyingDelta &&
                expectedUnderlyingDelta - vaultUnderlyingDelta > _MAX_CONVERT_ERROR) ||
            (vaultUnderlyingDelta > expectedUnderlyingDelta &&
                vaultUnderlyingDelta - expectedUnderlyingDelta > _MAX_CONVERT_ERROR)
        ) {
            // If this error is thrown, it means the convert result had an absolute error greater than
            // _MAX_CONVERT_ERROR in comparison with the actual operation.
            revert WrongUnderlyingAmount(address(wrappedToken));
        }

        if (
            ((vaultWrappedDelta > expectedWrappedDelta) &&
                (vaultWrappedDelta - expectedWrappedDelta > _MAX_CONVERT_ERROR)) ||
            (vaultWrappedDelta < expectedWrappedDelta && expectedWrappedDelta - vaultWrappedDelta > _MAX_CONVERT_ERROR)
        ) {
            // If this error is thrown, it means the convert result had an absolute error greater than
            // _MAX_CONVERT_ERROR in comparison with the actual operation.
            revert WrongWrappedAmount(address(wrappedToken));
        }
    }

    /**
     * @dev IERC4626 convert and preview may have different results for the same input, and preview is usually more
     * accurate, but more expensive than convert. _MAX_CONVERT_ERROR limits the error between these two functions and
     * allow us to use convert safely.
     */
    function _addConvertError(uint256 amount) private pure returns (uint256) {
        return amount + _MAX_CONVERT_ERROR;
    }

    /*******************************************************************************
                                    Pool Information
    *******************************************************************************/

    /// @inheritdoc IVaultMain
    function getPoolTokenCountAndIndexOfToken(
        address pool,
        IERC20 token
    ) external view withRegisteredPool(pool) returns (uint256, uint256) {
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances = _poolTokenBalances[pool];
        uint256 tokenCount = poolTokenBalances.length();
        // unchecked indexOf returns index + 1, or 0 if token is not present.
        uint256 index = poolTokenBalances.unchecked_indexOf(token);
        if (index == 0) {
            revert TokenNotRegistered();
        }

        unchecked {
            return (tokenCount, index - 1);
        }
    }

    /*******************************************************************************
                                    Authentication
    *******************************************************************************/

    /// @inheritdoc IVaultMain
    function getAuthorizer() external view returns (IAuthorizer) {
        return _authorizer;
    }

    /*******************************************************************************
                                     Default handlers
    *******************************************************************************/

    receive() external payable {
        revert CannotReceiveEth();
    }

    // solhint-disable no-complex-fallback

    /**
     * @inheritdoc Proxy
     * @dev Override proxy implementation of `fallback` to disallow incoming ETH transfers.
     * This function actually returns whatever the Vault Extension does when handling the request.
     */
    fallback() external payable override {
        if (msg.value > 0) {
            revert CannotReceiveEth();
        }

        _fallback();
    }

    /// @inheritdoc IVaultMain
    function getVaultExtension() external view returns (address) {
        return _implementation();
    }

    /**
     * @inheritdoc Proxy
     * @dev Returns Vault Extension, where fallback requests are forwarded.
     */
    function _implementation() internal view override returns (address) {
        return address(_vaultExtension);
    }
}
