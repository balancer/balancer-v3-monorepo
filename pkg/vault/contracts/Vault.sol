// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Proxy } from "@openzeppelin/contracts/proxy/Proxy.sol";

import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StorageSlotExtension } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { PackedTokenBalance } from "@balancer-labs/v3-solidity-utils/contracts/helpers/PackedTokenBalance.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { BufferHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/BufferHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

import { VaultStateLib, VaultStateBits } from "./lib/VaultStateLib.sol";
import { HooksConfigLib } from "./lib/HooksConfigLib.sol";
import { PoolConfigLib } from "./lib/PoolConfigLib.sol";
import { PoolDataLib } from "./lib/PoolDataLib.sol";
import { BasePoolMath } from "./BasePoolMath.sol";
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

    // When using the ERC4626 buffer liquidity directly to wrap/unwrap, convert is used to calculate how many tokens to
    // return to the user. However, convert is not equal to the actual operation and may return an optimistic result.
    // This factor makes sure that the use of buffer liquidity does not return more tokens than executing the
    // wrap/unwrap operation directly.
    uint16 internal constant _CONVERT_FACTOR = 100;

    // Local reference to the Proxy pattern Vault extension contract.
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

        _MINIMUM_TRADE_AMOUNT = IVaultAdmin(address(vaultExtension)).getMinimumTradeAmount();
        _MINIMUM_WRAP_AMOUNT = IVaultAdmin(address(vaultExtension)).getMinimumWrapAmount();

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
        VaultSwapParams memory vaultSwapParams
    )
        external
        onlyWhenUnlocked
        withInitializedPool(vaultSwapParams.pool)
        returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut)
    {
        _ensureUnpaused(vaultSwapParams.pool);

        if (vaultSwapParams.amountGivenRaw == 0) {
            revert AmountGivenZero();
        }

        if (vaultSwapParams.tokenIn == vaultSwapParams.tokenOut) {
            revert CannotSwapSameToken();
        }

        // `_loadPoolDataUpdatingBalancesAndYieldFees` is non-reentrant, as it updates storage as well
        // as filling in poolData in memory. Since the swap hooks are reentrant and could do anything, including
        // change these balances, we cannot defer settlement until `_swap`.
        //
        // Sets all fields in `poolData`. Side effects: updates `_poolTokenBalances`, `_aggregateFeeAmounts`
        // in storage.
        PoolData memory poolData = _loadPoolDataUpdatingBalancesAndYieldFees(vaultSwapParams.pool, Rounding.ROUND_DOWN);
        SwapState memory swapState = _loadSwapState(vaultSwapParams, poolData);
        PoolSwapParams memory poolSwapParams = _buildPoolSwapParams(vaultSwapParams, swapState, poolData);

        if (poolData.poolConfigBits.shouldCallBeforeSwap()) {
            HooksConfigLib.callBeforeSwapHook(
                poolSwapParams,
                vaultSwapParams.pool,
                _hooksContracts[vaultSwapParams.pool]
            );

            // The call to `onBeforeSwap` could potentially update token rates and balances.
            // We update `poolData.tokenRates`, `poolData.rawBalances` and `poolData.balancesLiveScaled18`
            // to ensure the `onSwap` and `onComputeDynamicSwapFeePercentage` are called with the current values.
            poolData.reloadBalancesAndRates(_poolTokenBalances[vaultSwapParams.pool], Rounding.ROUND_DOWN);

            // Also update amountGivenScaled18, as it will now be used in the swap, and the rates might have changed.
            swapState.amountGivenScaled18 = _computeAmountGivenScaled18(vaultSwapParams, poolData, swapState);

            poolSwapParams = _buildPoolSwapParams(vaultSwapParams, swapState, poolData);
        }

        _ensureValidTradeAmount(swapState.amountGivenScaled18);

        // Note that this must be called *after* the before hook, to guarantee that the swap params are the same
        // as those passed to the main operation.
        //
        // At this point, the static swap fee percentage is loaded in the `swapState` as the default, to be used
        // unless the pool has a dynamic swap fee. It is also passed into the hook, to support common cases
        // where the dynamic fee computation logic uses it.
        if (poolData.poolConfigBits.shouldCallComputeDynamicSwapFee()) {
            swapState.swapFeePercentage = HooksConfigLib.callComputeDynamicSwapFeeHook(
                poolSwapParams,
                vaultSwapParams.pool,
                swapState.swapFeePercentage,
                _hooksContracts[vaultSwapParams.pool]
            );
        }

        // Non-reentrant call that updates accounting.
        // The following side-effects are important to note:
        // PoolData balancesRaw and balancesLiveScaled18 are adjusted for swap amounts and fees inside of _swap.
        uint256 amountCalculatedScaled18;
        (amountCalculated, amountCalculatedScaled18, amountIn, amountOut) = _swap(
            vaultSwapParams,
            swapState,
            poolData,
            poolSwapParams
        );

        _ensureValidTradeAmount(amountCalculatedScaled18);

        // The new amount calculated is 'amountCalculated + delta'. If the underlying hook fails, or limits are
        // violated, `onAfterSwap` will revert. Uses msg.sender as the router (the contract that called the vault).
        if (poolData.poolConfigBits.shouldCallAfterSwap()) {
            // `hooksContract` needed to fix stack too deep.
            IHooks hooksContract = _hooksContracts[vaultSwapParams.pool];

            amountCalculated = poolData.poolConfigBits.callAfterSwapHook(
                amountCalculatedScaled18,
                amountCalculated,
                msg.sender,
                vaultSwapParams,
                swapState,
                poolData,
                hooksContract
            );
        }

        if (vaultSwapParams.kind == SwapKind.EXACT_IN) {
            amountOut = amountCalculated;
        } else {
            amountIn = amountCalculated;
        }
    }

    function _loadSwapState(
        VaultSwapParams memory vaultSwapParams,
        PoolData memory poolData
    ) private pure returns (SwapState memory swapState) {
        swapState.indexIn = _findTokenIndex(poolData.tokens, vaultSwapParams.tokenIn);
        swapState.indexOut = _findTokenIndex(poolData.tokens, vaultSwapParams.tokenOut);

        swapState.amountGivenScaled18 = _computeAmountGivenScaled18(vaultSwapParams, poolData, swapState);
        swapState.swapFeePercentage = poolData.poolConfigBits.getStaticSwapFeePercentage();
    }

    function _buildPoolSwapParams(
        VaultSwapParams memory vaultSwapParams,
        SwapState memory swapState,
        PoolData memory poolData
    ) internal view returns (PoolSwapParams memory) {
        // Uses msg.sender as the router (the contract that called the vault)
        return
            PoolSwapParams({
                kind: vaultSwapParams.kind,
                amountGivenScaled18: swapState.amountGivenScaled18,
                balancesScaled18: poolData.balancesLiveScaled18,
                indexIn: swapState.indexIn,
                indexOut: swapState.indexOut,
                router: msg.sender,
                userData: vaultSwapParams.userData
            });
    }

    /**
     * @dev Preconditions: decimalScalingFactors and tokenRates in `poolData` must be current.
     * Uses amountGivenRaw and kind from `vaultSwapParams`.
     */
    function _computeAmountGivenScaled18(
        VaultSwapParams memory vaultSwapParams,
        PoolData memory poolData,
        SwapState memory swapState
    ) private pure returns (uint256) {
        // If the amountGiven is entering the pool math (ExactIn), round down, since a lower apparent amountIn leads
        // to a lower calculated amountOut, favoring the pool.
        return
            vaultSwapParams.kind == SwapKind.EXACT_IN
                ? vaultSwapParams.amountGivenRaw.toScaled18ApplyRateRoundDown(
                    poolData.decimalScalingFactors[swapState.indexIn],
                    poolData.tokenRates[swapState.indexIn]
                )
                : vaultSwapParams.amountGivenRaw.toScaled18ApplyRateRoundUp(
                    poolData.decimalScalingFactors[swapState.indexOut],
                    // If the swap is ExactOut, the amountGiven is the amount of tokenOut. So, we want to use the rate
                    // rounded up to calculate the amountGivenScaled18, because if this value is bigger, the
                    // amountCalculatedRaw will be bigger, implying that the user will pay for any rounding
                    // inconsistency, and not the Vault.
                    poolData.tokenRates[swapState.indexOut].computeRateRoundUp()
                );
    }

    struct SwapInternalLocals {
        uint256 swapFeeAmountScaled18;
        uint256 swapFeeAmountRaw;
        uint256 aggregateFeeAmountRaw;
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
        VaultSwapParams memory vaultSwapParams,
        SwapState memory swapState,
        PoolData memory poolData,
        PoolSwapParams memory poolSwapParams
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

        if (vaultSwapParams.kind == SwapKind.EXACT_IN) {
            // Round up to avoid losses during precision loss.
            locals.swapFeeAmountScaled18 = poolSwapParams.amountGivenScaled18.mulUp(swapState.swapFeePercentage);
            poolSwapParams.amountGivenScaled18 -= locals.swapFeeAmountScaled18;
        }

        // Perform the swap request hook and compute the new balances for 'token in' and 'token out' after the swap.
        amountCalculatedScaled18 = IBasePool(vaultSwapParams.pool).onSwap(poolSwapParams);

        // Note that balances are kept in memory, and are not fully computed until the `setPoolBalances` below.
        // Intervening code cannot read balances from storage, as they are temporarily out-of-sync here. This function
        // is nonReentrant, to guard against read-only reentrancy issues.

        // (1) and (2): get raw amounts and check limits.
        if (vaultSwapParams.kind == SwapKind.EXACT_IN) {
            // Restore the original input value; this function should not mutate memory inputs.
            // At this point swap fee amounts have already been computed for EXACT_IN.
            poolSwapParams.amountGivenScaled18 = swapState.amountGivenScaled18;

            // For `ExactIn` the amount calculated is leaving the Vault, so we round down.
            amountCalculatedRaw = amountCalculatedScaled18.toRawUndoRateRoundDown(
                poolData.decimalScalingFactors[swapState.indexOut],
                // If the swap is ExactIn, the amountCalculated is the amount of tokenOut. So, we want to use the rate
                // rounded up to calculate the amountCalculatedRaw, because scale down (undo rate) is a division, the
                // larger the rate, the smaller the amountCalculatedRaw. So, any rounding imprecision will stay in the
                // Vault and not be drained by the user.
                poolData.tokenRates[swapState.indexOut].computeRateRoundUp()
            );

            (amountInRaw, amountOutRaw) = (vaultSwapParams.amountGivenRaw, amountCalculatedRaw);

            if (amountOutRaw < vaultSwapParams.limitRaw) {
                revert SwapLimit(amountOutRaw, vaultSwapParams.limitRaw);
            }
        } else {
            // To ensure symmetry with EXACT_IN, the swap fee used by ExactOut is
            // `amountCalculated * fee% / (100% - fee%)`. Add it to the calculated amountIn. Round up to avoid losses
            // during precision loss.
            locals.swapFeeAmountScaled18 = amountCalculatedScaled18.mulDivUp(
                swapState.swapFeePercentage,
                swapState.swapFeePercentage.complement()
            );

            amountCalculatedScaled18 += locals.swapFeeAmountScaled18;

            // For `ExactOut` the amount calculated is entering the Vault, so we round up.
            amountCalculatedRaw = amountCalculatedScaled18.toRawUndoRateRoundUp(
                poolData.decimalScalingFactors[swapState.indexIn],
                poolData.tokenRates[swapState.indexIn]
            );

            (amountInRaw, amountOutRaw) = (amountCalculatedRaw, vaultSwapParams.amountGivenRaw);

            if (amountInRaw > vaultSwapParams.limitRaw) {
                revert SwapLimit(amountInRaw, vaultSwapParams.limitRaw);
            }
        }

        // 3) Deltas: debit for token in, credit for token out.
        _takeDebt(vaultSwapParams.tokenIn, amountInRaw);
        _supplyCredit(vaultSwapParams.tokenOut, amountOutRaw);

        // 4) Compute and charge protocol and creator fees.
        // Note that protocol fee storage is updated before balance storage, as the final raw balances need to take
        // the fees into account.
        (locals.swapFeeAmountRaw, locals.aggregateFeeAmountRaw) = _computeAndChargeAggregateSwapFees(
            poolData,
            locals.swapFeeAmountScaled18,
            vaultSwapParams.pool,
            vaultSwapParams.tokenIn,
            swapState.indexIn
        );

        // 5) Pool balances: raw and live.

        poolData.updateRawAndLiveBalance(
            swapState.indexIn,
            poolData.balancesRaw[swapState.indexIn] + amountInRaw - locals.aggregateFeeAmountRaw,
            Rounding.ROUND_DOWN
        );
        poolData.updateRawAndLiveBalance(
            swapState.indexOut,
            poolData.balancesRaw[swapState.indexOut] - amountOutRaw,
            Rounding.ROUND_DOWN
        );

        // 6) Store pool balances, raw and live (only index in and out).
        mapping(uint256 tokenIndex => bytes32 packedTokenBalance) storage poolBalances = _poolTokenBalances[
            vaultSwapParams.pool
        ];
        poolBalances[swapState.indexIn] = PackedTokenBalance.toPackedBalance(
            poolData.balancesRaw[swapState.indexIn],
            poolData.balancesLiveScaled18[swapState.indexIn]
        );
        poolBalances[swapState.indexOut] = PackedTokenBalance.toPackedBalance(
            poolData.balancesRaw[swapState.indexOut],
            poolData.balancesLiveScaled18[swapState.indexOut]
        );

        // 7) Off-chain events.
        emit Swap(
            vaultSwapParams.pool,
            vaultSwapParams.tokenIn,
            vaultSwapParams.tokenOut,
            amountInRaw,
            amountOutRaw,
            swapState.swapFeePercentage,
            locals.swapFeeAmountRaw
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
        uint256 aggregateSwapFeeAmountRaw;
        uint256 tokenIndex;
    }

    /**
     * @dev Calls the appropriate pool hook and calculates the required inputs and outputs for the operation
     * considering the given kind, and updates the Vault's internal accounting. This includes:
     * - Setting pool balances
     * - Taking debt from the liquidity provider
     * - Minting pool tokens
     * - Emitting events
     *
     * It is non-reentrant, as it performs external calls and updates the Vault's state accordingly.
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
        amountsInRaw = new uint256[](locals.numTokens);
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
            // Deep copy given max amounts in raw to calculated amounts in raw to avoid scaling later, ensuring that
            // `maxAmountsIn` is preserved.
            ScalingHelpers.copyToArray(params.maxAmountsIn, amountsInRaw);

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

        for (uint256 i = 0; i < locals.numTokens; ++i) {
            uint256 amountInRaw;

            // 1) Calculate raw amount in.
            {
                uint256 amountInScaled18 = amountsInScaled18[i];
                _ensureValidTradeAmount(amountInScaled18);

                // If the value in memory is not set, convert scaled amount to raw.
                if (amountsInRaw[i] == 0) {
                    // amountsInRaw are amounts actually entering the Pool, so we round up.
                    // Do not mutate in place yet, as we need them scaled for the `onAfterAddLiquidity` hook.
                    amountInRaw = amountInScaled18.toRawUndoRateRoundUp(
                        poolData.decimalScalingFactors[i],
                        poolData.tokenRates[i]
                    );

                    amountsInRaw[i] = amountInRaw;
                } else {
                    // Exact in requests will have the raw amount in memory already, so we use it moving forward and
                    // skip unscaling.
                    amountInRaw = amountsInRaw[i];
                }
            }

            IERC20 token = poolData.tokens[i];

            // 2) Check limits for raw amounts.
            if (amountInRaw > params.maxAmountsIn[i]) {
                revert AmountInAboveMax(token, amountInRaw, params.maxAmountsIn[i]);
            }

            // 3) Deltas: Debit of token[i] for amountInRaw.
            _takeDebt(token, amountInRaw);

            // 4) Compute and charge protocol and creator fees.
            (, locals.aggregateSwapFeeAmountRaw) = _computeAndChargeAggregateSwapFees(
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
                poolData.balancesRaw[i] + amountInRaw - locals.aggregateSwapFeeAmountRaw,
                Rounding.ROUND_DOWN
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
     * considering the given kind, and updates the Vault's internal accounting. This includes:
     * - Setting pool balances
     * - Supplying credit to the liquidity provider
     * - Burning pool tokens
     * - Emitting events
     *
     * It is non-reentrant, as it performs external calls and updates the Vault's state accordingly.
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
        amountsOutRaw = new uint256[](locals.numTokens);

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
            amountsOutRaw[locals.tokenIndex] = params.minAmountsOut[locals.tokenIndex];

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

        for (uint256 i = 0; i < locals.numTokens; ++i) {
            uint256 amountOutRaw;

            // 1) Calculate raw amount out.
            {
                uint256 amountOutScaled18 = amountsOutScaled18[i];
                _ensureValidTradeAmount(amountOutScaled18);

                // If the value in memory is not set, convert scaled amount to raw.
                if (amountsOutRaw[i] == 0) {
                    // amountsOut are amounts exiting the Pool, so we round down.
                    // Do not mutate in place yet, as we need them scaled for the `onAfterRemoveLiquidity` hook.
                    amountOutRaw = amountOutScaled18.toRawUndoRateRoundDown(
                        poolData.decimalScalingFactors[i],
                        poolData.tokenRates[i]
                    );
                    amountsOutRaw[i] = amountOutRaw;
                } else {
                    // Exact out requests will have the raw amount in memory already, so we use it moving forward and
                    // skip unscaling.
                    amountOutRaw = amountsOutRaw[i];
                }
            }

            IERC20 token = poolData.tokens[i];
            // 2) Check limits for raw amounts.
            if (amountOutRaw < params.minAmountsOut[i]) {
                revert AmountOutBelowMin(token, amountOutRaw, params.minAmountsOut[i]);
            }

            // 3) Deltas: Credit token[i] for amountOutRaw.
            _supplyCredit(token, amountOutRaw);

            // 4) Compute and charge protocol and creator fees.
            (, locals.aggregateSwapFeeAmountRaw) = _computeAndChargeAggregateSwapFees(
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
                poolData.balancesRaw[i] - (amountOutRaw + locals.aggregateSwapFeeAmountRaw),
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
        // Burning will be reverted if it results in a total supply less than the _POOL_MINIMUM_TOTAL_SUPPLY.
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
     * @return swapFeeAmountRaw Total swap fees raw (LP + aggregate protocol fees)
     * @return aggregateSwapFeeAmountRaw Sum of protocol and pool creator fees raw
     */
    function _computeAndChargeAggregateSwapFees(
        PoolData memory poolData,
        uint256 swapFeeAmountScaled18,
        address pool,
        IERC20 token,
        uint256 index
    ) internal returns (uint256 swapFeeAmountRaw, uint256 aggregateSwapFeeAmountRaw) {
        uint256 aggregateSwapFeePercentage = poolData.poolConfigBits.getAggregateSwapFeePercentage();
        // If swapFeeAmount equals zero, no need to charge anything.
        if (
            swapFeeAmountScaled18 > 0 &&
            aggregateSwapFeePercentage > 0 &&
            poolData.poolConfigBits.isPoolInRecoveryMode() == false
        ) {
            swapFeeAmountRaw = swapFeeAmountScaled18.toRawUndoRateRoundUp(
                poolData.decimalScalingFactors[index],
                poolData.tokenRates[index]
            );

            // We have already calculated raw total fees rounding up.
            // Total fees = LP fees + aggregate fees, so by rounding aggregate fees down we round the fee split in
            // LPs' favor.
            aggregateSwapFeeAmountRaw = swapFeeAmountRaw.mulDown(aggregateSwapFeePercentage);

            // Ensure we can never charge more than the total swap fee.
            if (aggregateSwapFeeAmountRaw > swapFeeAmountRaw) {
                revert ProtocolFeesExceedTotalCollected();
            }

            // Both Swap and Yield fees are stored together in a PackedTokenBalance.
            // We have designated "Raw" the derived half for Swap fee storage.
            bytes32 currentPackedBalance = _aggregateFeeAmounts[pool][token];
            _aggregateFeeAmounts[pool][token] = currentPackedBalance.setBalanceRaw(
                currentPackedBalance.getBalanceRaw() + aggregateSwapFeeAmountRaw
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
                                  ERC4626 Buffers
    *******************************************************************************/

    /// @inheritdoc IVaultMain
    function erc4626BufferWrapOrUnwrap(
        BufferWrapOrUnwrapParams memory params
    )
        external
        onlyWhenUnlocked
        whenVaultBuffersAreNotPaused
        withInitializedBuffer(params.wrappedToken)
        nonReentrant
        returns (uint256 amountCalculatedRaw, uint256 amountInRaw, uint256 amountOutRaw)
    {
        IERC20 underlyingToken = IERC20(params.wrappedToken.asset());
        _ensureCorrectBufferAsset(params.wrappedToken, address(underlyingToken));

        if (params.amountGivenRaw < _MINIMUM_WRAP_AMOUNT) {
            // If amount given is too small, rounding issues can be introduced that favors the user and can drain
            // the buffer. _MINIMUM_WRAP_AMOUNT prevents it. Most tokens have protections against it already, this
            // is just an extra layer of security.
            revert WrapAmountTooSmall(params.wrappedToken);
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
        if (kind == SwapKind.EXACT_IN) {
            // EXACT_IN wrap, so AmountGiven is an underlying amount. `deposit` is the ERC4626 operation that receives
            // an underlying amount in and calculates the wrapped amount out with the correct rounding.
            (amountInUnderlying, amountOutWrapped) = (amountGiven, wrappedToken.previewDeposit(amountGiven));
        } else {
            // EXACT_OUT wrap, so AmountGiven is a wrapped amount. `mint` is the ERC4626 operation that receives a
            // wrapped amount out and calculates the underlying amount in with the correct rounding.
            (amountInUnderlying, amountOutWrapped) = (wrappedToken.previewMint(amountGiven), amountGiven);
        }

        // If it's a query, the Vault may not have enough underlying tokens to wrap. Since in a query we do not expect
        // the sender to pay for underlying tokens to wrap upfront, return the calculated amount without checking for
        // the surplus.
        if (_isQueryContext()) {
            return (amountInUnderlying, amountOutWrapped);
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

            // Expected amount of underlying deposited into the wrapper protocol.
            uint256 vaultUnderlyingDeltaHint;
            // Expected amount of wrapped minted by the wrapper protocol.
            uint256 vaultWrappedDeltaHint;

            if (kind == SwapKind.EXACT_IN) {
                // The amount of underlying tokens to deposit is the necessary amount to fulfill the trade
                // (amountInUnderlying), plus the amount needed to leave the buffer rebalanced 50/50 at the end
                // (bufferUnderlyingSurplus).
                vaultUnderlyingDeltaHint = amountInUnderlying + bufferUnderlyingSurplus;
                underlyingToken.forceApprove(address(wrappedToken), vaultUnderlyingDeltaHint);
                // EXACT_IN requires the exact amount of underlying tokens to be deposited, so we call deposit.
                vaultWrappedDeltaHint = wrappedToken.deposit(vaultUnderlyingDeltaHint, address(this));
            } else {
                if (bufferUnderlyingSurplus > 0) {
                    // A wrap operation withdraws underlying tokens from the buffer and mints wrapped tokens in return.
                    // For the buffer to rebalance during a wrap operation, it must have an excess (surplus) of
                    // underlying tokens. Since this is an EXACT_OUT wrap (mint), we need to calculate the amount of
                    // wrapped tokens the buffer should receive to rebalance, based on the underlying token surplus.
                    // The deposit function is used here, as it performs the inverse of a mint operation.
                    bufferWrappedSurplus = wrappedToken.previewDeposit(bufferUnderlyingSurplus);
                }

                // The mint operation returns exactly `vaultWrappedDelta` shares. To do so, it withdraws underlying
                // from the Vault and returns the shares. So, the vault needs to approve the transfer of underlying
                // tokens to the wrapper.
                underlyingToken.forceApprove(address(wrappedToken), amountInUnderlying + bufferUnderlyingSurplus);

                // EXACT_OUT requires the exact amount of wrapped tokens to be returned, so mint is called.
                vaultWrappedDeltaHint = amountOutWrapped + bufferWrappedSurplus;
                vaultUnderlyingDeltaHint = wrappedToken.mint(vaultWrappedDeltaHint, address(this));
            }

            // Remove approval, in case deposit/mint consumed less tokens than we approved.
            // E.g., A malicious wrapper could not consume all of the underlying tokens and use the vault approval to
            // drain the vault.
            underlyingToken.forceApprove(address(wrappedToken), 0);

            // Check if the Vault's underlying balance decreased by `vaultUnderlyingDeltaHint` and the Vault's
            // wrapped balance increased by `vaultWrappedDeltaHint`. If not, it reverts.
            _settleWrap(underlyingToken, IERC20(wrappedToken), vaultUnderlyingDeltaHint, vaultWrappedDeltaHint);

            // Only updates buffer balances if buffer has a surplus of underlying tokens.
            if (bufferUnderlyingSurplus > 0) {
                if (kind == SwapKind.EXACT_IN) {
                    // Since `bufferUnderlyingSurplus` was wrapped, the final amount out needs to discount the wrapped
                    // amount that will stay in the buffer. Refresh `bufferWrappedSurplus` after external calls on the
                    // wrapped token. For EXACT_IN, `vaultUnderlyingDeltaHint` and `amountInUnderlying` do not change
                    // after the deposit operation, so the `bufferUnderlyingSurplus` does not need to be recalculated.
                    bufferWrappedSurplus = wrappedToken.previewDeposit(bufferUnderlyingSurplus);
                    amountOutWrapped = vaultWrappedDeltaHint - bufferWrappedSurplus;
                } else {
                    // If the buffer has a surplus of underlying tokens, it wraps the surplus + amountIn, so the final
                    // amount in needs to be discounted for that. For EXACT_OUT, `vaultWrappedDeltaHint` and
                    // `amountOutWrapped` do not change after the mint operation, so the `bufferWrappedSurplus` does
                    // not need to be recalculated.
                    bufferUnderlyingSurplus = wrappedToken.previewMint(bufferWrappedSurplus);
                    amountInUnderlying = vaultUnderlyingDeltaHint - bufferUnderlyingSurplus;
                }

                // In a wrap operation, the underlying balance of the buffer will decrease and the wrapped balance will
                // increase. To decrease the underlying balance, we get the delta amount that was deposited
                // (vaultUnderlyingDeltaHint) and discount the amount needed for the wrapping operation
                // (amountInUnderlying). The same logic applies to wrapped balances.
                //
                // Note: bufferUnderlyingSurplus = vaultUnderlyingDeltaHint - amountInUnderlying
                //       bufferWrappedSurplus = vaultWrappedDeltaHint - amountOutWrapped
                bufferBalances = PackedTokenBalance.toPackedBalance(
                    bufferBalances.getBalanceRaw() - bufferUnderlyingSurplus,
                    bufferBalances.getBalanceDerived() + bufferWrappedSurplus
                );
                _bufferTokenBalances[wrappedToken] = bufferBalances;
            } else {
                amountInUnderlying = vaultUnderlyingDeltaHint;
                amountOutWrapped = vaultWrappedDeltaHint;
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
        if (kind == SwapKind.EXACT_IN) {
            // EXACT_IN unwrap, so AmountGiven is a wrapped amount. `redeem` is the ERC4626 operation that receives a
            // wrapped amount in and calculates the underlying amount out with the correct rounding.
            (amountInWrapped, amountOutUnderlying) = (amountGiven, wrappedToken.previewRedeem(amountGiven));
        } else {
            // EXACT_OUT unwrap, so AmountGiven is an underlying amount. `withdraw` is the ERC4626 operation that
            // receives an underlying amount out and calculates the wrapped amount in with the correct rounding.
            (amountInWrapped, amountOutUnderlying) = (wrappedToken.previewWithdraw(amountGiven), amountGiven);
        }

        // If it's a query, the Vault may not have enough wrapped tokens to unwrap. Since in a query we do not expect
        // the sender to pay for wrapped tokens to unwrap upfront, return the calculated amount without checking for
        // the surplus.
        if (_isQueryContext()) {
            return (amountInWrapped, amountOutUnderlying);
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
            // surplus of wrapped tokens.

            // Gets the amount of wrapped tokens to unwrap in order to rebalance the buffer.
            uint256 bufferWrappedSurplus = bufferBalances.getBufferWrappedSurplus(wrappedToken);
            uint256 bufferUnderlyingSurplus;

            // Expected amount of underlying withdrawn from the wrapper protocol.
            uint256 vaultUnderlyingDeltaHint;
            // Expected amount of wrapped burned by the wrapper protocol.
            uint256 vaultWrappedDeltaHint;

            if (kind == SwapKind.EXACT_IN) {
                // EXACT_IN requires the exact amount of wrapped tokens to be unwrapped, so we call redeem.
                // The amount of wrapped tokens to redeem is the amount necessary to fulfill the trade
                // (amountInWrapped), plus the amount needed to leave the buffer rebalanced 50/50 at the end
                // (bufferWrappedSurplus).
                vaultWrappedDeltaHint = amountInWrapped + bufferWrappedSurplus;
                vaultUnderlyingDeltaHint = wrappedToken.redeem(vaultWrappedDeltaHint, address(this), address(this));
            } else {
                // EXACT_OUT requires the exact amount of underlying tokens to be returned, so we call withdraw.
                // The amount of underlying tokens to withdraw is the amount necessary to fulfill the trade
                // (amountOutUnderlying), plus the amount needed to leave the buffer rebalanced 50/50 at the end
                // (bufferUnderlyingSurplus).
                if (bufferWrappedSurplus > 0) {
                    // An unwrap operation withdraws wrapped tokens from the buffer and returns underlying tokens.
                    // For the buffer to rebalance during an unwrap operation, it must have an excess (surplus) of
                    // wrapped tokens. Since this is an EXACT_OUT unwrap (withdraw), we need to calculate the amount of
                    // underlying tokens the buffer should receive to rebalance, based on the wrapped token surplus.
                    // The redeem function is used here, as it performs the inverse of a withdraw operation.
                    bufferUnderlyingSurplus = wrappedToken.previewRedeem(bufferWrappedSurplus);
                }
                vaultUnderlyingDeltaHint = amountOutUnderlying + bufferUnderlyingSurplus;
                vaultWrappedDeltaHint = wrappedToken.withdraw(vaultUnderlyingDeltaHint, address(this), address(this));
            }

            // Check if the Vault's underlying balance increased by `vaultUnderlyingDeltaHint` and the Vault's
            // wrapped balance decreased by `vaultWrappedDeltaHint`. If not, it reverts.
            _settleUnwrap(underlyingToken, IERC20(wrappedToken), vaultUnderlyingDeltaHint, vaultWrappedDeltaHint);

            // Only updates buffer balances if buffer has a surplus of wrapped tokens.
            if (bufferWrappedSurplus > 0) {
                if (kind == SwapKind.EXACT_IN) {
                    // Since bufferWrappedSurplus was unwrapped, the final amountOut needs to discount the underlying
                    // amount that will stay in the buffer. Refresh `bufferUnderlyingSurplus` after external calls
                    // on the wrapped token. For EXACT_IN, `vaultWrappedDeltaHint` and `amountInWrapped` do not change
                    // after the redeem operation, so the `bufferWrappedSurplus` does not need to be recalculated.
                    bufferUnderlyingSurplus = wrappedToken.previewRedeem(bufferWrappedSurplus);
                    amountOutUnderlying = vaultUnderlyingDeltaHint - bufferUnderlyingSurplus;
                } else {
                    // If the buffer has a surplus of wrapped tokens, it unwraps the surplus + amountIn, so the final
                    // amountIn needs to be discounted for that. For EXACT_OUT, `vaultUnderlyingDeltaHint` and
                    // `amountOutUnderlying` do not change after the withdraw operation, so the
                    // `bufferUnderlyingSurplus` does not need to be recalculated.
                    bufferWrappedSurplus = wrappedToken.previewWithdraw(bufferUnderlyingSurplus);
                    amountInWrapped = vaultWrappedDeltaHint - bufferWrappedSurplus;
                }

                // In an unwrap operation, the underlying balance of the buffer will increase and the wrapped balance
                // will decrease. To increase the underlying balance, we get the delta amount that was withdrawn
                // (vaultUnderlyingDeltaHint) and discount the amount needed for the unwrapping operation
                // (amountOutUnderlying). The same logic applies to wrapped balances.
                //
                // Note: bufferUnderlyingSurplus = vaultUnderlyingDeltaHint - amountOutUnderlying
                //       bufferWrappedSurplus = vaultWrappedDeltaHint - amountInWrapped
                bufferBalances = PackedTokenBalance.toPackedBalance(
                    bufferBalances.getBalanceRaw() + bufferUnderlyingSurplus,
                    bufferBalances.getBalanceDerived() - bufferWrappedSurplus
                );
                _bufferTokenBalances[wrappedToken] = bufferBalances;
            } else {
                amountOutUnderlying = vaultUnderlyingDeltaHint;
                amountInWrapped = vaultWrappedDeltaHint;
            }
        }

        _takeDebt(wrappedToken, amountInWrapped);
        _supplyCredit(underlyingToken, amountOutUnderlying);
    }

    function _isQueryContext() internal view returns (bool) {
        return EVMCallModeHelpers.isStaticCall() && _vaultStateBits.isQueryDisabled() == false;
    }

    /**
     * @notice Updates the reserves of the vault after an ERC4626 wrap (deposit/mint) operation.
     * @dev If there are extra tokens in the vault balances, these will be added to the reserves (which, in practice,
     * is equal to discarding such tokens). This approach avoids DoS attacks, when a frontrunner leaves vault balances
     * and reserves out of sync before a transaction starts.
     *
     * @param underlyingToken Underlying token of the ERC4626 wrapped token
     * @param wrappedToken ERC4626 wrapped token
     * @param underlyingDeltaHint Amount of underlying tokens the wrapper should have removed from the Vault
     * @param wrappedDeltaHint Amount of wrapped tokens the wrapper should have added to the Vault
     */
    function _settleWrap(
        IERC20 underlyingToken,
        IERC20 wrappedToken,
        uint256 underlyingDeltaHint,
        uint256 wrappedDeltaHint
    ) internal {
        // A wrap operation removes underlying tokens from the Vault, so the Vault's expected underlying balance after
        // the operation is `underlyingReservesBefore - underlyingDeltaHint`.
        uint256 expectedUnderlyingReservesAfter = _reservesOf[underlyingToken] - underlyingDeltaHint;

        // A wrap operation adds wrapped tokens to the vault, so the Vault's expected wrapped balance after the
        // operation is `wrappedReservesBefore + wrappedDeltaHint`.
        uint256 expectedWrappedReservesAfter = _reservesOf[wrappedToken] + wrappedDeltaHint;

        _settleWrapUnwrap(underlyingToken, wrappedToken, expectedUnderlyingReservesAfter, expectedWrappedReservesAfter);
    }

    /**
     * @notice Updates the reserves of the vault after an ERC4626 unwrap (withdraw/redeem) operation.
     * @dev If there are extra tokens in the vault balances, these will be added to the reserves (which, in practice,
     * is equal to discarding such tokens). This approach avoids DoS attacks, when a frontrunner leaves vault balances
     * and state of reserves out of sync before a transaction starts.
     *
     * @param underlyingToken Underlying of ERC4626 wrapped token
     * @param wrappedToken ERC4626 wrapped token
     * @param underlyingDeltaHint Amount of underlying tokens supposedly added to the vault
     * @param wrappedDeltaHint Amount of wrapped tokens supposedly removed from the Vault
     */
    function _settleUnwrap(
        IERC20 underlyingToken,
        IERC20 wrappedToken,
        uint256 underlyingDeltaHint,
        uint256 wrappedDeltaHint
    ) internal {
        // An unwrap operation adds underlying tokens to the vault, so the Vault's expected underlying balance after
        // the operation is `underlyingReservesBefore + underlyingDeltaHint`.
        uint256 expectedUnderlyingReservesAfter = _reservesOf[underlyingToken] + underlyingDeltaHint;

        // An unwrap operation removes wrapped tokens from the Vault, so the Vault's expected wrapped balance after the
        // operation is `wrappedReservesBefore - wrappedDeltaHint`.
        uint256 expectedWrappedReservesAfter = _reservesOf[wrappedToken] - wrappedDeltaHint;

        _settleWrapUnwrap(underlyingToken, wrappedToken, expectedUnderlyingReservesAfter, expectedWrappedReservesAfter);
    }

    /**
     * @notice Updates the reserves of the vault after an ERC4626 wrap/unwrap operation.
     * @dev If reserves of underlying or wrapped tokens are bigger than expected, the extra tokens will be discarded,
     * which avoids a possible DoS. However, if reserves are smaller than expected, it means that the wrapper didn't
     * respect the amount given and/or the amount calculated (informed by the wrapper operation and stored as a hint
     * variable), so the token is not ERC4626 compliant and the function should be reverted.
     *
     * @param underlyingToken Underlying of ERC4626 wrapped token
     * @param wrappedToken ERC4626 wrapped token
     * @param expectedUnderlyingReservesAfter Vault's expected reserves of underlying after the wrap/unwrap operation
     * @param expectedWrappedReservesAfter Vault's expected reserves of wrapped after the wrap/unwrap operation
     */
    function _settleWrapUnwrap(
        IERC20 underlyingToken,
        IERC20 wrappedToken,
        uint256 expectedUnderlyingReservesAfter,
        uint256 expectedWrappedReservesAfter
    ) private {
        // Update the Vault's underlying reserves.
        uint256 underlyingBalancesAfter = underlyingToken.balanceOf(address(this));
        if (underlyingBalancesAfter < expectedUnderlyingReservesAfter) {
            // If Vault's underlying balance is smaller than expected, the Vault was drained and the operation should
            // revert. It may happen in different ways, depending on the wrap/unwrap operation:
            // * deposit: the wrapper didn't respect the exact amount in of underlying;
            // * mint: the underlying amount subtracted from the vault is bigger than wrapper's calculated amount in;
            // * withdraw: the wrapper didn't respect the exact amount out of underlying;
            // * redeem: the underlying amount added to the vault is smaller than wrapper's calculated amount out.
            revert NotEnoughUnderlying(
                IERC4626(address(wrappedToken)),
                expectedUnderlyingReservesAfter,
                underlyingBalancesAfter
            );
        }
        // Update the Vault's underlying reserves, discarding any unexpected surplus of tokens (difference between
        // actual and expected vault balance).
        _reservesOf[underlyingToken] = underlyingBalancesAfter;

        // Update the Vault's wrapped reserves.
        uint256 wrappedBalancesAfter = wrappedToken.balanceOf(address(this));
        if (wrappedBalancesAfter < expectedWrappedReservesAfter) {
            // If the Vault's wrapped balance is smaller than expected, the Vault was drained and the operation should
            // revert. It may happen in different ways, depending on the wrap/unwrap operation:
            // * deposit: the wrapped amount added to the vault is smaller than wrapper's calculated amount out;
            // * mint: the wrapper didn't respect the exact amount out of wrapped;
            // * withdraw: the wrapped amount subtracted from the vault is bigger than wrapper's calculated amount in;
            // * redeem: the wrapper didn't respect the exact amount in of wrapped.
            revert NotEnoughWrapped(
                IERC4626(address(wrappedToken)),
                expectedWrappedReservesAfter,
                wrappedBalancesAfter
            );
        }
        // Update the Vault's wrapped reserves, discarding any unexpected surplus of tokens (difference between Vault's
        // actual and expected balances).
        _reservesOf[wrappedToken] = wrappedBalancesAfter;
    }

    // Minimum swap amount (applied to scaled18 values), enforced as a security measure to block potential
    // exploitation of rounding errors.
    function _ensureValidTradeAmount(uint256 tradeAmount) private view {
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
     * This function actually returns whatever the VaultExtension does when handling the request.
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
     * @dev Returns the VaultExtension contract, to which fallback requests are forwarded.
     */
    function _implementation() internal view override returns (address) {
        return address(_vaultExtension);
    }
}
