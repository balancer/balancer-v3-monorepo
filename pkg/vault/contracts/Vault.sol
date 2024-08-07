// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Proxy } from "@openzeppelin/contracts/proxy/Proxy.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { StorageSlotExtension } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";
import { PackedTokenBalance } from "@balancer-labs/v3-solidity-utils/contracts/helpers/PackedTokenBalance.sol";
import { BufferHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/BufferHelpers.sol";

import { VaultStateLib, VaultStateBits } from "./lib/VaultStateLib.sol";
import { PoolConfigLib } from "./lib/PoolConfigLib.sol";
import { HooksConfigLib } from "./lib/HooksConfigLib.sol";
import { PoolDataLib } from "./lib/PoolDataLib.sol";
import { VaultCommon } from "./VaultCommon.sol";

contract Vault is IVaultMain, VaultCommon, Proxy {
    using PackedTokenBalance for bytes32;
    using BufferHelpers for bytes32;
    using InputHelpers for uint256;
    using FixedPoint for *;
    using Address for *;
    using CastingHelpers for uint256[];
    using SafeERC20 for IERC20;
    using PoolConfigLib for PoolConfigBits;
    using HooksConfigLib for PoolConfigBits;
    using VaultStateLib for VaultStateBits;
    using ScalingHelpers for *;
    using TransientStorageHelpers for *;
    using StorageSlotExtension for *;
    using PoolDataLib for PoolData;

    IVaultExtension private immutable _vaultExtension;

    constructor(IVaultExtension vaultExtension, IAuthorizer authorizer, IProtocolFeeController protocolFeeController) {
        if (address(vaultExtension.vault()) != address(this)) {
            revert WrongVaultExtensionDeployment();
        }

        if (address(protocolFeeController.vault()) != address(this)) {
            revert WrongProtocolFeeControllerDeployment();
        }

        _vaultExtension = vaultExtension;
        _protocolFeeController = protocolFeeController;

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
     * This is useful for functions like `unlock`, which perform arbitrary external calls:
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
            if (_nonZeroDeltaCount().tload() != 0) {
                revert BalanceNotSettled();
            }

            _isUnlocked().tstore(false);
        }
    }

    /// @inheritdoc IVaultMain
    function unlock(bytes calldata data) external transient returns (bytes memory result) {
        return (msg.sender).functionCall(data);
    }

    /// @inheritdoc IVaultMain
    function settle(IERC20 token, uint256 amountHint) external nonReentrant onlyWhenUnlocked returns (uint256 credit) {
        uint256 reservesBefore = _reservesOf[token];
        uint256 currentReserves = token.balanceOf(address(this));
        _reservesOf[token] = currentReserves;
        credit = currentReserves - reservesBefore;

        // If the given hint is equal or greater to the reserve difference, we just take the actual reserve difference
        // as the paid amount; the actual balance of the tokens in the vault is what matters here.
        if (credit > amountHint) {
            // If the difference in reserves is higher than the amount claimed to be paid by the caller, there was some
            // leftover that had been sent to the vault beforehand, which was not incorporated into the reserves.
            // In that case, we simply discard the leftover by considering the given hint as the amount paid.
            // In turn, this gives the caller credit for the given amount hint, which is what the caller is expecting.
            credit = amountHint;
        }

        _supplyCredit(token, credit);
    }

    /// @inheritdoc IVaultMain
    function sendTo(IERC20 token, address to, uint256 amount) external nonReentrant onlyWhenUnlocked {
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
    // This reasoning applies to Weighted Pool math, and is likely to apply to others as well, but of course
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
        external
        onlyWhenUnlocked
        withInitializedPool(params.pool)
        returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut)
    {
        _ensureUnpaused(params.pool);

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
        // Sets all fields in `poolData`. Side effects: updates `_poolTokenBalances`, `_aggregateFeeAmounts`
        // in storage.
        PoolData memory poolData = _loadPoolDataUpdatingBalancesAndYieldFees(params.pool, Rounding.ROUND_DOWN);

        // State is fully populated here, and shall not be modified at a lower level.
        SwapState memory state = _loadSwapState(params, poolData);

        PoolSwapParams memory swapParams = _buildPoolSwapParams(params, state, poolData);

        if (poolData.poolConfigBits.shouldCallBeforeSwap()) {
            HooksConfigLib.callBeforeSwapHook(swapParams, params.pool, _hooksContracts[params.pool]);

            // The call to `onBeforeSwap` could potentially update token rates and balances.
            // We update `poolData.tokenRates`, `poolData.rawBalances` and `poolData.balancesLiveScaled18`
            // to ensure the `onSwap` and `onComputeDynamicSwapFeePercentage` are called with the current values.
            poolData.reloadBalancesAndRates(_poolTokenBalances[params.pool], Rounding.ROUND_DOWN);

            // Also update amountGivenScaled18, as it will now be used in the swap, and the rates might have changed.
            state.amountGivenScaled18 = _computeAmountGivenScaled18(params, poolData, state);

            swapParams = _buildPoolSwapParams(params, state, poolData);
        }

        _ensureValidTradeAmount(state.amountGivenScaled18);

        // Note that this must be called *after* the before hook, to guarantee that the swap params are the same
        // as those passed to the main operation.
        //
        // At this point, the static swap fee percentage is loaded in the swap state as the default, to be used
        // unless the pool has a dynamic swap fee. It is also passed into the hook, to support common cases
        // where the dynamic fee computation logic uses it.
        if (poolData.poolConfigBits.shouldCallComputeDynamicSwapFee()) {
            (bool dynamicSwapFeeCalculated, uint256 dynamicSwapFee) = HooksConfigLib.callComputeDynamicSwapFeeHook(
                swapParams,
                params.pool,
                state.swapFeePercentage,
                _hooksContracts[params.pool]
            );

            if (dynamicSwapFeeCalculated) {
                state.swapFeePercentage = dynamicSwapFee;
            }
        }

        // Non-reentrant call that updates accounting.
        // The following side-effects are important to note:
        // PoolData balancesRaw and balancesLiveScaled18 are adjusted for swap amounts and fees inside of _swap.
        uint256 amountCalculatedScaled18;
        (amountCalculated, amountCalculatedScaled18, amountIn, amountOut) = _swap(params, state, poolData, swapParams);

        _ensureValidTradeAmount(amountCalculatedScaled18);

        // The new amount calculated is 'amountCalculated + delta'. If the underlying hook fails, or limits are
        // violated, `onAfterSwap` will revert. Uses msg.sender as the router (the contract that called the vault).
        if (poolData.poolConfigBits.shouldCallAfterSwap()) {
            // `hooksContract` needed to fix stack too deep.
            IHooks hooksContract = _hooksContracts[params.pool];

            amountCalculated = poolData.poolConfigBits.callAfterSwapHook(
                amountCalculatedScaled18,
                amountCalculated,
                msg.sender,
                params,
                state,
                poolData,
                hooksContract
            );
        }

        if (params.kind == SwapKind.EXACT_IN) {
            amountOut = amountCalculated;
        } else {
            amountIn = amountCalculated;
        }
    }

    function _loadSwapState(
        SwapParams memory params,
        PoolData memory poolData
    ) private pure returns (SwapState memory state) {
        state.indexIn = _findTokenIndex(poolData.tokens, params.tokenIn);
        state.indexOut = _findTokenIndex(poolData.tokens, params.tokenOut);

        // If the amountGiven is entering the pool math (ExactIn), round down, since a lower apparent amountIn leads
        // to a lower calculated amountOut, favoring the pool.
        state.amountGivenScaled18 = _computeAmountGivenScaled18(params, poolData, state);
        state.swapFeePercentage = poolData.poolConfigBits.getStaticSwapFeePercentage();
    }

    function _buildPoolSwapParams(
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    ) internal view returns (PoolSwapParams memory) {
        // Uses msg.sender as the router (the contract that called the vault)
        return
            PoolSwapParams({
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
        SwapParams memory params,
        PoolData memory poolData,
        SwapState memory state
    ) private pure returns (uint256) {
        // If the amountGiven is entering the pool math (ExactIn), round down, since a lower apparent amountIn leads
        // to a lower calculated amountOut, favoring the pool.
        return
            params.kind == SwapKind.EXACT_IN
                ? params.amountGivenRaw.toScaled18ApplyRateRoundDown(
                    poolData.decimalScalingFactors[state.indexIn],
                    poolData.tokenRates[state.indexIn]
                )
                : params.amountGivenRaw.toScaled18ApplyRateRoundUp(
                    poolData.decimalScalingFactors[state.indexOut],
                    poolData.tokenRates[state.indexOut]
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
     * Updates `_aggregateFeeAmounts`, and `_poolTokenBalances` in storage.
     * Emits Swap event.
     */
    function _swap(
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData,
        PoolSwapParams memory swapParams
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

        // Perform the swap request hook and compute the new balances for 'token in' and 'token out' after the swap.
        amountCalculatedScaled18 = IBasePool(params.pool).onSwap(swapParams);

        // Note that balances are kept in memory, and are not fully computed until the `setPoolBalances` below.
        // Intervening code cannot read balances from storage, as they are temporarily out-of-sync here. This function
        // is nonReentrant, to guard against read-only reentrancy issues.

        // (1) and (2): get raw amounts and check limits.
        if (params.kind == SwapKind.EXACT_IN) {
            // Swap fee is always a percentage of the amountCalculated. On ExactIn, subtract it from the calculated
            // amountOut. Round up to avoid losses during precision loss.
            locals.swapFeeAmountScaled18 = amountCalculatedScaled18.mulUp(state.swapFeePercentage);

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
            // To ensure symmetry with EXACT_IN, the swap fee used by ExactOut is
            // `amountCalculated * fee% / (100% - fee%)`. Add it to the calculated amountIn. Round up to avoid losses
            // during precision loss.
            locals.swapFeeAmountScaled18 = amountCalculatedScaled18.mulDivUp(
                state.swapFeePercentage,
                state.swapFeePercentage.complement()
            );

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

        // 3) Deltas: debit for token in, credit for token out.
        _takeDebt(params.tokenIn, amountInRaw);
        _supplyCredit(params.tokenOut, amountOutRaw);

        // 4) Compute and charge protocol and creator fees.
        (locals.swapFeeIndex, locals.swapFeeToken) = params.kind == SwapKind.EXACT_IN
            ? (state.indexOut, params.tokenOut)
            : (state.indexIn, params.tokenIn);

        // Note that protocol fee storage is updated before balance storage, as the final raw balances need to take
        // the fees into account.
        uint256 totalFeesRaw = _computeAndChargeAggregateSwapFees(
            poolData,
            locals.swapFeeAmountScaled18,
            params.pool,
            locals.swapFeeToken,
            locals.swapFeeIndex
        );

        // 5) Pool balances: raw and live.
        //
        // Adjust for raw swap amounts and total fees on the calculated end.
        // So that fees are always subtracted from pool balances:
        // For ExactIn, we increase the tokenIn balance by `amountIn`, and decrease the tokenOut balance by the
        // (`amountOut` + fees).
        // For ExactOut, we increase the tokenInBalance by (`amountIn` - fees), and decrease the tokenOut balance by
        // `amountOut`.
        (locals.balanceInIncrement, locals.balanceOutDecrement) = params.kind == SwapKind.EXACT_IN
            ? (amountInRaw, amountOutRaw + totalFeesRaw)
            : (amountInRaw - totalFeesRaw, amountOutRaw);

        poolData.updateRawAndLiveBalance(
            state.indexIn,
            poolData.balancesRaw[state.indexIn] + locals.balanceInIncrement,
            Rounding.ROUND_UP
        );
        poolData.updateRawAndLiveBalance(
            state.indexOut,
            poolData.balancesRaw[state.indexOut] - locals.balanceOutDecrement,
            Rounding.ROUND_DOWN
        );

        // 6) Store pool balances, raw and live (only index in and out).
        mapping(uint256 => bytes32) storage poolBalances = _poolTokenBalances[params.pool];
        poolBalances[state.indexIn] = PackedTokenBalance.toPackedBalance(
            poolData.balancesRaw[state.indexIn],
            poolData.balancesLiveScaled18[state.indexIn]
        );
        poolBalances[state.indexOut] = PackedTokenBalance.toPackedBalance(
            poolData.balancesRaw[state.indexOut],
            poolData.balancesLiveScaled18[state.indexOut]
        );

        // 7) Off-chain events.
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

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

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

        _ensureUnpaused(params.pool);

        // `_loadPoolDataUpdatingBalancesAndYieldFees` is non-reentrant, as it updates storage as well
        // as filling in poolData in memory. Since the add liquidity hooks are reentrant and could do anything,
        // including change these balances, we cannot defer settlement until `_addLiquidity`.
        //
        // Sets all fields in `poolData`. Side effects: updates `_poolTokenBalances`, and
        // `_aggregateFeeAmounts` in storage.
        PoolData memory poolData = _loadPoolDataUpdatingBalancesAndYieldFees(params.pool, Rounding.ROUND_UP);
        InputHelpers.ensureInputLengthMatch(poolData.tokens.length, params.maxAmountsIn.length);

        // Amounts are entering pool math, so round down.
        // Introducing `maxAmountsInScaled18` here and passing it through to _addLiquidity is not ideal,
        // but it avoids the even worse options of mutating amountsIn inside AddLiquidityParams,
        // or cluttering the AddLiquidityParams interface by adding amountsInScaled18.
        uint256[] memory maxAmountsInScaled18 = params.maxAmountsIn.copyToScaled18ApplyRateRoundDownArray(
            poolData.decimalScalingFactors,
            poolData.tokenRates
        );

        if (poolData.poolConfigBits.shouldCallBeforeAddLiquidity()) {
            HooksConfigLib.callBeforeAddLiquidityHook(
                msg.sender,
                maxAmountsInScaled18,
                params,
                poolData,
                _hooksContracts[params.pool]
            );
            // The hook might have altered the balances, so we need to read them again to ensure that the data
            // are fresh moving forward. We also need to upscale (adding liquidity, so round up) again.
            poolData.reloadBalancesAndRates(_poolTokenBalances[params.pool], Rounding.ROUND_UP);

            // Also update maxAmountsInScaled18, as the rates might have changed.
            maxAmountsInScaled18 = params.maxAmountsIn.copyToScaled18ApplyRateRoundDownArray(
                poolData.decimalScalingFactors,
                poolData.tokenRates
            );
        }

        // The bulk of the work is done here: the corresponding Pool hook is called, and the final balances
        // are computed. This function is non-reentrant, as it performs the accounting updates.
        //
        // Note that poolData is mutated to update the Raw and Live balances, so they are accurate when passed
        // into the AfterAddLiquidity hook.
        //
        // `amountsInScaled18` will be overwritten in the custom case, so we need to pass it back and forth to
        // encapsulate that logic in `_addLiquidity`.
        uint256[] memory amountsInScaled18;
        (amountsIn, amountsInScaled18, bptAmountOut, returnData) = _addLiquidity(
            poolData,
            params,
            maxAmountsInScaled18
        );

        // AmountsIn can be changed by onAfterAddLiquidity if the hook charges fees or gives discounts.
        // Uses msg.sender as the router (the contract that called the vault).
        if (poolData.poolConfigBits.shouldCallAfterAddLiquidity()) {
            // `hooksContract` needed to fix stack too deep.
            IHooks hooksContract = _hooksContracts[params.pool];

            amountsIn = poolData.poolConfigBits.callAfterAddLiquidityHook(
                msg.sender,
                amountsInScaled18,
                amountsIn,
                bptAmountOut,
                params,
                poolData,
                hooksContract
            );
        }
    }

    // Avoid "stack too deep" - without polluting the Add/RemoveLiquidity params interface.
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
        locals.numTokens = poolData.tokens.length;
        uint256[] memory swapFeeAmountsScaled18;

        if (params.kind == AddLiquidityKind.PROPORTIONAL) {
            bptAmountOut = params.minBptAmountOut;
            // Initializes the swapFeeAmountsScaled18 empty array (no swap fees on proportional add liquidity).
            swapFeeAmountsScaled18 = new uint256[](locals.numTokens);

            amountsInScaled18 = BasePoolMath.computeProportionalAmountsIn(
                poolData.balancesLiveScaled18,
                _totalSupply(params.pool),
                bptAmountOut
            );
        } else if (params.kind == AddLiquidityKind.DONATION) {
            poolData.poolConfigBits.requireDonationEnabled();

            swapFeeAmountsScaled18 = new uint256[](maxAmountsInScaled18.length);
            bptAmountOut = 0;
            amountsInScaled18 = maxAmountsInScaled18;
        } else if (params.kind == AddLiquidityKind.UNBALANCED) {
            poolData.poolConfigBits.requireUnbalancedLiquidityEnabled();

            amountsInScaled18 = maxAmountsInScaled18;
            (bptAmountOut, swapFeeAmountsScaled18) = BasePoolMath.computeAddLiquidityUnbalanced(
                poolData.balancesLiveScaled18,
                maxAmountsInScaled18,
                _totalSupply(params.pool),
                poolData.poolConfigBits.getStaticSwapFeePercentage(),
                IBasePool(params.pool)
            );
        } else if (params.kind == AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            poolData.poolConfigBits.requireUnbalancedLiquidityEnabled();

            bptAmountOut = params.minBptAmountOut;
            locals.tokenIndex = InputHelpers.getSingleInputIndex(maxAmountsInScaled18);

            amountsInScaled18 = maxAmountsInScaled18;
            (amountsInScaled18[locals.tokenIndex], swapFeeAmountsScaled18) = BasePoolMath
                .computeAddLiquiditySingleTokenExactOut(
                    poolData.balancesLiveScaled18,
                    locals.tokenIndex,
                    bptAmountOut,
                    _totalSupply(params.pool),
                    poolData.poolConfigBits.getStaticSwapFeePercentage(),
                    IBasePool(params.pool)
                );
        } else if (params.kind == AddLiquidityKind.CUSTOM) {
            poolData.poolConfigBits.requireAddCustomLiquidityEnabled();

            // Uses msg.sender as the router (the contract that called the vault).
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

        _ensureValidTradeAmount(bptAmountOut);

        amountsInRaw = new uint256[](locals.numTokens);

        for (uint256 i = 0; i < locals.numTokens; ++i) {
            uint256 amountInRaw;

            // 1) Calculate raw amount in.
            {
                uint256 amountInScaled18 = amountsInScaled18[i];
                _ensureValidTradeAmount(amountInScaled18);

                // amountsInRaw are amounts actually entering the Pool, so we round up.
                // Do not mutate in place yet, as we need them scaled for the `onAfterAddLiquidity` hook.
                amountInRaw = amountInScaled18.toRawUndoRateRoundUp(
                    poolData.decimalScalingFactors[i],
                    poolData.tokenRates[i]
                );

                amountsInRaw[i] = amountInRaw;
            }

            IERC20 token = poolData.tokens[i];

            // 2) Check limits for raw amounts.
            if (amountInRaw > params.maxAmountsIn[i]) {
                revert AmountInAboveMax(token, amountInRaw, params.maxAmountsIn[i]);
            }

            // 3) Deltas: Debit of token[i] for amountInRaw.
            _takeDebt(token, amountInRaw);

            // 4) Compute and charge protocol and creator fees.
            locals.totalFeesRaw = _computeAndChargeAggregateSwapFees(
                poolData,
                swapFeeAmountsScaled18[i],
                params.pool,
                token,
                i
            );

            // 5) Pool balances: raw and live.
            // We need regular balances to complete the accounting, and the upscaled balances
            // to use in the `after` hook later on.

            // A pool's token balance increases by amounts in after adding liquidity, minus fees.
            poolData.updateRawAndLiveBalance(
                i,
                poolData.balancesRaw[i] + amountInRaw - locals.totalFeesRaw,
                Rounding.ROUND_UP
            );
        }

        // 6) Store pool balances, raw and live.
        _writePoolBalancesToStorage(params.pool, poolData);

        // 7) BPT supply adjustment.
        // When adding liquidity, we must mint tokens concurrently with updating pool balances,
        // as the pool's math relies on totalSupply.
        _mint(address(params.pool), params.to, bptAmountOut);

        // 8) Off-chain events.
        emit PoolBalanceChanged(params.pool, params.to, amountsInRaw.unsafeCastToInt256(true));
    }

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

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
        _ensureUnpaused(params.pool);

        // `_loadPoolDataUpdatingBalancesAndYieldFees` is non-reentrant, as it updates storage as well
        // as filling in poolData in memory. Since the swap hooks are reentrant and could do anything, including
        // change these balances, we cannot defer settlement until `_removeLiquidity`.
        //
        // Sets all fields in `poolData`. Side effects: updates `_poolTokenBalances` and
        // `_aggregateFeeAmounts in storage.
        PoolData memory poolData = _loadPoolDataUpdatingBalancesAndYieldFees(params.pool, Rounding.ROUND_DOWN);
        InputHelpers.ensureInputLengthMatch(poolData.tokens.length, params.minAmountsOut.length);

        // Amounts are entering pool math; higher amounts would burn more BPT, so round up to favor the pool.
        // Do not mutate minAmountsOut, so that we can directly compare the raw limits later, without potentially
        // losing precision by scaling up and then down.
        uint256[] memory minAmountsOutScaled18 = params.minAmountsOut.copyToScaled18ApplyRateRoundUpArray(
            poolData.decimalScalingFactors,
            poolData.tokenRates
        );

        // Uses msg.sender as the router (the contract that called the vault).
        if (poolData.poolConfigBits.shouldCallBeforeRemoveLiquidity()) {
            HooksConfigLib.callBeforeRemoveLiquidityHook(
                minAmountsOutScaled18,
                msg.sender,
                params,
                poolData,
                _hooksContracts[params.pool]
            );

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
        //
        // Note that poolData is mutated to update the Raw and Live balances, so they are accurate when passed
        // into the AfterRemoveLiquidity hook.
        uint256[] memory amountsOutScaled18;
        (bptAmountIn, amountsOut, amountsOutScaled18, returnData) = _removeLiquidity(
            poolData,
            params,
            minAmountsOutScaled18
        );

        // AmountsOut can be changed by onAfterRemoveLiquidity if the hook charges fees or gives discounts.
        // Uses msg.sender as the router (the contract that called the vault).
        if (poolData.poolConfigBits.shouldCallAfterRemoveLiquidity()) {
            // `hooksContract` needed to fix stack too deep.
            IHooks hooksContract = _hooksContracts[params.pool];

            amountsOut = poolData.poolConfigBits.callAfterRemoveLiquidityHook(
                msg.sender,
                amountsOutScaled18,
                amountsOut,
                bptAmountIn,
                params,
                poolData,
                hooksContract
            );
        }
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
        uint256[] memory minAmountsOutScaled18
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
        locals.numTokens = poolData.tokens.length;
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
            poolData.poolConfigBits.requireUnbalancedLiquidityEnabled();
            bptAmountIn = params.maxBptAmountIn;
            amountsOutScaled18 = minAmountsOutScaled18;
            locals.tokenIndex = InputHelpers.getSingleInputIndex(params.minAmountsOut);

            (amountsOutScaled18[locals.tokenIndex], swapFeeAmountsScaled18) = BasePoolMath
                .computeRemoveLiquiditySingleTokenExactIn(
                    poolData.balancesLiveScaled18,
                    locals.tokenIndex,
                    bptAmountIn,
                    _totalSupply(params.pool),
                    poolData.poolConfigBits.getStaticSwapFeePercentage(),
                    IBasePool(params.pool)
                );
        } else if (params.kind == RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            poolData.poolConfigBits.requireUnbalancedLiquidityEnabled();
            amountsOutScaled18 = minAmountsOutScaled18;
            locals.tokenIndex = InputHelpers.getSingleInputIndex(params.minAmountsOut);

            (bptAmountIn, swapFeeAmountsScaled18) = BasePoolMath.computeRemoveLiquiditySingleTokenExactOut(
                poolData.balancesLiveScaled18,
                locals.tokenIndex,
                amountsOutScaled18[locals.tokenIndex],
                _totalSupply(params.pool),
                poolData.poolConfigBits.getStaticSwapFeePercentage(),
                IBasePool(params.pool)
            );
        } else if (params.kind == RemoveLiquidityKind.CUSTOM) {
            poolData.poolConfigBits.requireRemoveCustomLiquidityEnabled();
            // Uses msg.sender as the router (the contract that called the vault)
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

        _ensureValidTradeAmount(bptAmountIn);

        amountsOutRaw = new uint256[](locals.numTokens);

        for (uint256 i = 0; i < locals.numTokens; ++i) {
            uint256 amountOutRaw;

            // 1) Calculate raw amount out.
            {
                uint256 amountOutScaled18 = amountsOutScaled18[i];
                _ensureValidTradeAmount(amountOutScaled18);

                // amountsOut are amounts exiting the Pool, so we round down.
                // Do not mutate in place yet, as we need them scaled for the `onAfterRemoveLiquidity` hook.
                amountOutRaw = amountOutScaled18.toRawUndoRateRoundDown(
                    poolData.decimalScalingFactors[i],
                    poolData.tokenRates[i]
                );
            }

            amountsOutRaw[i] = amountOutRaw;

            IERC20 token = poolData.tokens[i];
            // 2) Check limits for raw amounts.
            if (amountOutRaw < params.minAmountsOut[i]) {
                revert AmountOutBelowMin(token, amountOutRaw, params.minAmountsOut[i]);
            }

            // 3) Deltas: Credit token[i] for amountOutRaw.
            _supplyCredit(token, amountOutRaw);

            // 4) Compute and charge protocol and creator fees.
            locals.totalFeesRaw = _computeAndChargeAggregateSwapFees(
                poolData,
                swapFeeAmountsScaled18[i],
                params.pool,
                token,
                i
            );

            // 5) Pool balances: raw and live.
            // We need regular balances to complete the accounting, and the upscaled balances
            // to use in the `after` hook later on.

            // A Pool's token balance always decreases after an exit
            // (potentially by 0). Also adjust by protocol and pool creator fees.
            poolData.updateRawAndLiveBalance(
                i,
                poolData.balancesRaw[i] - (amountOutRaw + locals.totalFeesRaw),
                Rounding.ROUND_DOWN
            );
        }

        // 6) Store pool balances, raw and live.
        _writePoolBalancesToStorage(params.pool, poolData);

        // 7) BPT supply adjustment.
        // Uses msg.sender as the router (the contract that called the vault).
        _spendAllowance(address(params.pool), params.from, msg.sender, bptAmountIn);

        if (_isQueryContext()) {
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
     * @dev Preconditions: poolConfigBits, decimalScalingFactors, tokenRates in `poolData`.
     * Side effects: updates `_aggregateFeeAmounts` storage.
     * Note that this computes the aggregate total of the protocol fees and stores it, without emitting any events.
     * Splitting the fees and event emission occur during fee collection.
     * Should only be called in a non-reentrant context.
     *
     * @return totalFeesRaw Sum of protocol and pool creator fees raw
     */
    function _computeAndChargeAggregateSwapFees(
        PoolData memory poolData,
        uint256 swapFeeAmountScaled18,
        address pool,
        IERC20 token,
        uint256 index
    ) internal returns (uint256 totalFeesRaw) {
        uint256 aggregateSwapFeePercentage = poolData.poolConfigBits.getAggregateSwapFeePercentage();
        // If swapFeeAmount equals zero, no need to charge anything.
        if (
            swapFeeAmountScaled18 > 0 &&
            aggregateSwapFeePercentage > 0 &&
            poolData.poolConfigBits.isPoolInRecoveryMode() == false
        ) {
            uint256 aggregateSwapFeeAmountScaled18 = swapFeeAmountScaled18.mulUp(aggregateSwapFeePercentage);

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
            bytes32 currentPackedBalance = _aggregateFeeAmounts[pool][token];
            _aggregateFeeAmounts[pool][token] = currentPackedBalance.setBalanceRaw(
                currentPackedBalance.getBalanceRaw() + totalFeesRaw
            );
        }
    }

    /*******************************************************************************
                                    Pool Information
    *******************************************************************************/

    /// @inheritdoc IVaultMain
    function getPoolTokenCountAndIndexOfToken(
        address pool,
        IERC20 token
    ) external view withRegisteredPool(pool) returns (uint256, uint256) {
        IERC20[] memory poolTokens = _poolTokens[pool];

        uint256 index = _findTokenIndex(poolTokens, token);

        return (poolTokens.length, index);
    }

    /*******************************************************************************
                             Yield-bearing token buffers
    *******************************************************************************/

    /// @inheritdoc IVaultMain
    function erc4626BufferWrapOrUnwrap(
        BufferWrapOrUnwrapParams memory params
    )
        external
        onlyWhenUnlocked
        whenVaultBuffersAreNotPaused
        nonReentrant
        returns (uint256 amountCalculatedRaw, uint256 amountInRaw, uint256 amountOutRaw)
    {
        IERC20 underlyingToken = IERC20(params.wrappedToken.asset());

        address bufferAsset = _bufferAssets[params.wrappedToken];

        if (bufferAsset != address(0) && bufferAsset != address(underlyingToken)) {
            // Asset was changed since the first addLiquidityToBuffer call.
            revert WrongWrappedTokenAsset(address(params.wrappedToken));
        }

        if (params.amountGivenRaw < _MINIMUM_WRAP_AMOUNT) {
            // If amount given is too small, rounding issues can be introduced that favors the user and can drain
            // the buffer. _MINIMUM_WRAP_AMOUNT prevents it. Most tokens have protections against it already, this
            // is just an extra layer of security.
            revert WrapAmountTooSmall(address(params.wrappedToken));
        }

        if (params.direction == WrappingDirection.UNWRAP) {
            (amountInRaw, amountOutRaw) = _unwrapWithBuffer(
                params.kind,
                underlyingToken,
                params.wrappedToken,
                params.amountGivenRaw
            );
            emit Unwrap(params.wrappedToken, underlyingToken, amountInRaw, amountOutRaw);
        } else {
            (amountInRaw, amountOutRaw) = _wrapWithBuffer(
                params.kind,
                underlyingToken,
                params.wrappedToken,
                params.amountGivenRaw
            );
            emit Wrap(underlyingToken, params.wrappedToken, amountInRaw, amountOutRaw);
        }

        if (params.kind == SwapKind.EXACT_IN) {
            if (amountOutRaw < params.limitRaw) {
                revert SwapLimit(amountOutRaw, params.limitRaw);
            }
            amountCalculatedRaw = amountOutRaw;
        } else {
            if (amountInRaw > params.limitRaw) {
                revert SwapLimit(amountInRaw, params.limitRaw);
            }
            amountCalculatedRaw = amountInRaw;
        }
    }

    /**
     * @dev If the buffer has enough liquidity, it uses the internal ERC4626 buffer to perform the wrap
     * operation without any external calls. If not, it wraps the assets needed to fulfill the trade + the surplus
     * of assets in the buffer, so that the buffer is rebalanced at the end of the operation.
     *
     * Updates `_reservesOf` and token deltas in storage.
     */
    function _wrapWithBuffer(
        SwapKind kind,
        IERC20 underlyingToken,
        IERC4626 wrappedToken,
        uint256 amountGiven
    ) private returns (uint256 amountInUnderlying, uint256 amountOutWrapped) {
        // When wrapping and in query mode, the vault needs to have enough reserves of underlying token to do the
        // wrap operation. If the vault does not have enough tokens to do the actual wrap, use ERC4626 preview.
        bool isQueryContext = _isQueryContext();

        if (kind == SwapKind.EXACT_IN) {
            if (isQueryContext) {
                return (amountGiven, wrappedToken.previewDeposit(amountGiven));
            }
            // EXACT_IN wrap, so AmountGiven is underlying amount.
            (amountInUnderlying, amountOutWrapped) = (amountGiven, wrappedToken.convertToShares(amountGiven));
        } else {
            if (isQueryContext) {
                return (wrappedToken.previewMint(amountGiven), amountGiven);
            }
            // EXACT_OUT wrap, so AmountGiven is wrapped amount.
            (amountInUnderlying, amountOutWrapped) = (wrappedToken.convertToAssets(amountGiven), amountGiven);
        }

        bytes32 bufferBalances = _bufferTokenBalances[wrappedToken];

        if (bufferBalances.getBalanceDerived() >= amountOutWrapped) {
            // The buffer has enough liquidity to facilitate the wrap without making an external call.
            uint256 newDerivedBalance;
            unchecked {
                // We have verified above that this is safe to do unchecked.
                newDerivedBalance = bufferBalances.getBalanceDerived() - amountOutWrapped;
            }

            bufferBalances = PackedTokenBalance.toPackedBalance(
                bufferBalances.getBalanceRaw() + amountInUnderlying,
                newDerivedBalance
            );
            _bufferTokenBalances[wrappedToken] = bufferBalances;
        } else {
            // The buffer does not have enough liquidity to facilitate the wrap without making an external call.
            // We wrap the user's tokens via an external call and additionally rebalance the buffer if it has a
            // surplus of underlying tokens.

            // Gets the amount of underlying to wrap in order to rebalance the buffer.
            uint256 bufferUnderlyingSurplus = bufferBalances.getBufferUnderlyingSurplus(wrappedToken);
            uint256 bufferWrappedSurplus;

            if (kind == SwapKind.EXACT_IN) {
                // The amount of underlying tokens to deposit is the necessary amount to fulfill the trade
                // (amountInUnderlying), plus the amount needed to leave the buffer rebalanced 50/50 at the end
                // (bufferUnderlyingSurplus).
                uint256 amountToDeposit = amountInUnderlying + bufferUnderlyingSurplus;
                underlyingToken.forceApprove(address(wrappedToken), amountToDeposit);
                // EXACT_IN requires the exact amount of underlying tokens to be deposited, so deposit is called.
                wrappedToken.deposit(amountToDeposit, address(this));
            } else {
                if (bufferUnderlyingSurplus > 0) {
                    bufferWrappedSurplus = wrappedToken.convertToShares(bufferUnderlyingSurplus);
                }

                // The mint operation returns exactly `vaultWrappedDelta` shares. To do so, it withdraws underlying
                // from the vault and returns the shares. So, the vault needs to approve the transfer of underlying
                // tokens to the wrapper.
                // Add 2 because mint can consume up to 2 wei more tokens than we anticipated.
                underlyingToken.forceApprove(address(wrappedToken), amountInUnderlying + bufferUnderlyingSurplus + 2);

                // EXACT_OUT requires the exact amount of wrapped tokens to be returned, so mint is called.
                wrappedToken.mint(amountOutWrapped + bufferWrappedSurplus, address(this));

                // Remove approval, in case mint consumed less tokens than we approved, due to convert error.
                underlyingToken.forceApprove(address(wrappedToken), 0);
            }

            // ERC4626 output should not be trusted, so it's a good practice to measure the amount of
            // deposited and returned tokens.
            (uint256 vaultUnderlyingDelta, uint256 vaultWrappedDelta) = _updateReservesAfterWrapping(
                underlyingToken,
                IERC20(wrappedToken)
            );

            // Only updates buffer balances if buffer has a surplus of underlying tokens.
            if (bufferUnderlyingSurplus > 0) {
                if (kind == SwapKind.EXACT_IN) {
                    // amountInUnderlying is the amountGiven and should not be changed. Any rounding issue that occurs
                    // in the vaultUnderlyingDelta should be absorbed by the buffer.
                    bufferUnderlyingSurplus = vaultUnderlyingDelta - amountInUnderlying;
                    // Since bufferUnderlyingSurplus was wrapped, the final amountOut needs to discount the wrapped
                    // amount that will stay in the buffer. Refresh `bufferWrappedSurplus` after external calls on the
                    // wrapped token.
                    bufferWrappedSurplus = wrappedToken.convertToShares(bufferUnderlyingSurplus);
                    amountOutWrapped = vaultWrappedDelta - bufferWrappedSurplus;
                } else {
                    // If buffer has an underlying surplus, it wraps the surplus + amountIn, so the final amountIn needs
                    // to be discounted for that.
                    amountInUnderlying = vaultUnderlyingDelta - bufferUnderlyingSurplus;
                    // amountOutWrapped is the amountGiven and should not be changed. Any rounding issue that occurs
                    // in the vaultWrappedDelta should be absorbed by the buffer.
                    bufferWrappedSurplus = vaultWrappedDelta - amountOutWrapped;
                }

                // In a wrap operation, the underlying balance of the buffer will decrease and the wrapped balance will
                // increase. To decrease underlying balance, we get the delta amount that was deposited
                // (vaultUnderlyingDelta) and discounts the amount needed in the wrapping operation
                // (amountInUnderlying). Same logic applies to wrapped balances.
                //
                // Note: bufferUnderlyingSurplus = vaultUnderlyingDelta - amountInUnderlying
                //       bufferWrappedSurplus = vaultWrappedDelta - amountOutWrapped
                bufferBalances = PackedTokenBalance.toPackedBalance(
                    bufferBalances.getBalanceRaw() - bufferUnderlyingSurplus,
                    bufferBalances.getBalanceDerived() + bufferWrappedSurplus
                );
                _bufferTokenBalances[wrappedToken] = bufferBalances;
            } else {
                amountInUnderlying = vaultUnderlyingDelta;
                amountOutWrapped = vaultWrappedDelta;
            }
        }

        _takeDebt(underlyingToken, amountInUnderlying);
        _supplyCredit(wrappedToken, amountOutWrapped);
    }

    /**
     * @dev If the buffer has enough liquidity, it uses the internal ERC4626 buffer to perform the unwrap
     * operation without any external calls. If not, it unwraps the assets needed to fulfill the trade + the surplus
     * of assets in the buffer, so that the buffer is rebalanced at the end of the operation.
     *
     * Updates `_reservesOf` and token deltas in storage.
     */
    function _unwrapWithBuffer(
        SwapKind kind,
        IERC20 underlyingToken,
        IERC4626 wrappedToken,
        uint256 amountGiven
    ) private returns (uint256 amountInWrapped, uint256 amountOutUnderlying) {
        bool isQueryContext = _isQueryContext();

        if (kind == SwapKind.EXACT_IN) {
            if (isQueryContext) {
                return (amountGiven, wrappedToken.previewRedeem(amountGiven));
            }
            // EXACT_IN unwrap, so AmountGiven is wrapped amount.
            (amountOutUnderlying, amountInWrapped) = (wrappedToken.convertToAssets(amountGiven), amountGiven);
        } else {
            if (isQueryContext) {
                return (wrappedToken.previewWithdraw(amountGiven), amountGiven);
            }
            // EXACT_OUT unwrap, so AmountGiven is underlying amount.
            (amountOutUnderlying, amountInWrapped) = (amountGiven, wrappedToken.convertToShares(amountGiven));
        }

        bytes32 bufferBalances = _bufferTokenBalances[wrappedToken];

        if (bufferBalances.getBalanceRaw() >= amountOutUnderlying) {
            // The buffer has enough liquidity to facilitate the wrap without making an external call.
            uint256 newRawBalance;
            unchecked {
                // We have verified above that this is safe to do unchecked.
                newRawBalance = bufferBalances.getBalanceRaw() - amountOutUnderlying;
            }
            bufferBalances = PackedTokenBalance.toPackedBalance(
                newRawBalance,
                bufferBalances.getBalanceDerived() + amountInWrapped
            );
            _bufferTokenBalances[wrappedToken] = bufferBalances;
        } else {
            // The buffer does not have enough liquidity to facilitate the unwrap without making an external call.
            // We unwrap the user's tokens via an external call and additionally rebalance the buffer if it has a
            // surplus of underlying tokens.

            // Gets the amount of wrapped tokens to unwrap in order to rebalance the buffer.
            uint256 bufferWrappedSurplus = bufferBalances.getBufferWrappedSurplus(wrappedToken);
            uint256 bufferUnderlyingSurplus;

            if (kind == SwapKind.EXACT_IN) {
                // EXACT_IN requires the exact amount of wrapped tokens to be unwrapped, so redeem is called
                // The amount of wrapped tokens to redeem is the necessary amount to fulfill the trade
                // (amountInWrapped), plus the amount needed to leave the buffer rebalanced 50/50 at the end
                // (bufferWrappedSurplus).
                wrappedToken.redeem(amountInWrapped + bufferWrappedSurplus, address(this), address(this));
            } else {
                // EXACT_OUT requires the exact amount of underlying tokens to be returned, so withdraw is called.
                // The amount of underlying tokens to withdraw is the necessary amount to fulfill the trade
                // (amountOutUnderlying), plus the amount needed to leave the buffer rebalanced 50/50 at the end
                // (bufferUnderlyingSurplus).
                if (bufferWrappedSurplus > 0) {
                    bufferUnderlyingSurplus = wrappedToken.convertToAssets(bufferWrappedSurplus);
                }
                wrappedToken.withdraw(amountOutUnderlying + bufferUnderlyingSurplus, address(this), address(this));
            }

            // ERC4626 output should not be trusted, so it's a good practice to measure the amount of
            // deposited and returned tokens.
            (uint256 vaultUnderlyingDelta, uint256 vaultWrappedDelta) = _updateReservesAfterWrapping(
                underlyingToken,
                IERC20(wrappedToken)
            );

            // Only updates buffer balances if buffer has a surplus of wrapped tokens.
            if (bufferWrappedSurplus > 0) {
                if (kind == SwapKind.EXACT_IN) {
                    // amountInWrapped is the amountGiven and should not be changed. Any rounding issue that occurs
                    // in the vaultWrappedDelta should be absorbed by the buffer.
                    bufferWrappedSurplus = vaultWrappedDelta - amountInWrapped;
                    // Since bufferWrappedSurplus was unwrapped, the final amountOut needs to discount the underlying
                    // amount that will stay in the buffer. Refresh `bufferUnderlyingSurplus` after external calls
                    // on the wrapped token.
                    bufferUnderlyingSurplus = wrappedToken.convertToAssets(bufferWrappedSurplus);
                    amountOutUnderlying = vaultUnderlyingDelta - bufferUnderlyingSurplus;
                } else {
                    // If buffer has a wrapped surplus, it unwraps surplus + amountIn, so the final amountIn needs to
                    // be discounted for that.
                    amountInWrapped = vaultWrappedDelta - bufferWrappedSurplus;
                    // amountOutUnderlying is the amountGiven and should not be changed. Any rounding issue that occurs
                    // in the vaultUnderlyingDelta should be absorbed by the buffer.
                    bufferUnderlyingSurplus = vaultUnderlyingDelta - amountOutUnderlying;
                }

                // In an unwrap operation, the underlying balance of the buffer will increase and the wrapped balance
                // will decrease. To increase the underlying balance, we get the delta amount that was withdrawn
                // (vaultUnderlyingDelta) and discount the amount expected in the unwrapping operation
                // (amountOutUnderlying). The same logic applies to wrapped balances.
                //
                // Note: bufferUnderlyingSurplus = vaultUnderlyingDelta - amountOutUnderlying
                //       bufferWrappedSurplus = vaultWrappedDelta - amountInWrapped
                bufferBalances = PackedTokenBalance.toPackedBalance(
                    bufferBalances.getBalanceRaw() + bufferUnderlyingSurplus,
                    bufferBalances.getBalanceDerived() - bufferWrappedSurplus
                );
                _bufferTokenBalances[wrappedToken] = bufferBalances;
            } else {
                amountOutUnderlying = vaultUnderlyingDelta;
                amountInWrapped = vaultWrappedDelta;
            }
        }

        _takeDebt(wrappedToken, amountInWrapped);
        _supplyCredit(underlyingToken, amountOutUnderlying);
    }

    function _isQueryContext() internal view returns (bool) {
        return EVMCallModeHelpers.isStaticCall() && _vaultStateBits.isQueryDisabled() == false;
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

        uint256 vaultWrappedBefore = _reservesOf[wrappedToken];
        uint256 vaultWrappedAfter = wrappedToken.balanceOf(address(this));
        _reservesOf[wrappedToken] = vaultWrappedAfter;

        if (vaultUnderlyingBefore > vaultUnderlyingAfter) {
            // Wrap
            // Since deposit takes underlying tokens from the vault, the actual underlying tokens deposited is
            // underlyingBefore - underlyingAfter
            // checked against underflow: vaultUnderlyingBefore > vaultUnderlyingAfter in `if` clause.
            unchecked {
                vaultUnderlyingDelta = vaultUnderlyingBefore - vaultUnderlyingAfter;
            }
            // Since deposit puts wrapped tokens into the vault, the actual wrapped minted is
            // wrappedAfter - wrappedBefore.
            vaultWrappedDelta = vaultWrappedAfter - vaultWrappedBefore;
        } else {
            // Unwrap
            // Since withdraw puts underlying tokens into the vault, the actual underlying token amount withdrawn is
            // assetsAfter - assetsBefore.
            // checked against underflow: vaultUnderlyingAfter > vaultUnderlyingBefore in `else` clause.
            unchecked {
                vaultUnderlyingDelta = vaultUnderlyingAfter - vaultUnderlyingBefore;
            }
            // Since withdraw takes wrapped tokens from the vault, the actual wrapped token amount burned is
            // wrappedBefore - wrappedAfter.
            vaultWrappedDelta = vaultWrappedBefore - vaultWrappedAfter;
        }
    }

    // Minimum swap amount (applied to scaled18 values), enforced as a security measure to block potential
    // exploitation of rounding errors.
    function _ensureValidTradeAmount(uint256 tradeAmount) private pure {
        if (tradeAmount != 0 && tradeAmount < _MINIMUM_TRADE_AMOUNT) {
            revert TradeAmountTooSmall();
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

    /*******************************************************************************
                                     Miscellaneous
    *******************************************************************************/

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
