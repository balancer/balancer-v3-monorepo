// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Proxy } from "@openzeppelin/contracts/proxy/Proxy.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IBufferPool } from "@balancer-labs/v3-interfaces/contracts/vault/IBufferPool.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

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
import { PackedTokenBalance } from "./lib/PackedTokenBalance.sol";
import { PoolDataLib } from "./lib/PoolDataLib.sol";
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
    using ScalingHelpers for *;
    using VaultStateLib for VaultStateBits;
    using TransientStorageHelpers for *;
    using StorageSlot for *;
    using PoolDataLib for PoolData;

    constructor(IVaultExtension vaultExtension, IAuthorizer authorizer) {
        if (address(vaultExtension.vault()) != address(this)) {
            revert WrongVaultExtensionDeployment();
        }

        _vaultExtension = vaultExtension;

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
        VaultState memory vaultState = _ensureUnpausedAndGetVaultState(params.pool);

        if (params.amountGivenRaw == 0) {
            revert AmountGivenZero();
        }

        if (params.tokenIn == params.tokenOut) {
            revert CannotSwapSameToken();
        }

        // `_chargePendingYieldFeesUpdatePoolBalancesAndLoadPoolData` is non-reentrant, as it updates storage as well as filling in
        // poolData in memory. Since the swap hooks are reentrant and could do anything, including change these
        // balances, we cannot defer settlement until `_swap`.
        //
        // Sets all fields in `poolData`. Side effects: updates `_poolTokenBalances`, `_protocolFees`,
        // `_poolCreatorFees` in storage. May emit ProtocolYieldFeeCharged and PoolCreatorYieldFeeCharged events.
        PoolData memory poolData = _chargePendingYieldFeesUpdatePoolBalancesAndLoadPoolData(
            params.pool,
            Rounding.ROUND_DOWN,
            vaultState.protocolYieldFeePercentage
        );

        SwapVars memory vars;

        (vars.indexIn, vars.indexOut) = _getSwapTokenIndexes(params);

        // If the amountGiven is entering the pool math (ExactIn), round down, since a lower apparent amountIn leads
        // to a lower calculated amountOut, favoring the pool.
        //_updateAmountGivenInVars(vars, params, poolData);
        vars.amountGivenScaled18 = _computeAmountGivenScaled18(vars, params, poolData);

        if (poolData.poolConfig.hooks.shouldCallBeforeSwap) {
            if (IPoolHooks(params.pool).onBeforeSwap(_buildPoolSwapParams(params, vars, poolData)) == false) {
                revert BeforeSwapHookFailed();
            }

            // The call to `onBeforeSwap` could potentially update token rates and balances.
            // We update `poolData.tokenRates`, `poolData.rawBalances` and `poolData.balancesLiveScaled18`
            // to ensure the `onSwap` and `onComputeDynamicSwapFee` are called with the current values.
            poolData.reloadPossiblyStaleBalancesAndTokenRates(_poolTokenBalances[params.pool], Rounding.ROUND_DOWN);

            // Also update amountGivenScaled18, as it will now be used in the swap, and the rates might have changed.
            //_updateAmountGivenInVars(vars, params, poolData);
            vars.amountGivenScaled18 = _computeAmountGivenScaled18(vars, params, poolData);
        }

        // Note that this must be called *after* the before hook, to guarantee that the swap params are the same
        // as those passed to the main operation.
        if (poolData.poolConfig.hooks.shouldCallComputeDynamicSwapFee) {
            bool success;

            (success, vars.swapFeePercentage) = IPoolHooks(params.pool).onComputeDynamicSwapFee(
                _buildPoolSwapParams(params, vars, poolData)
            );

            if (success == false) {
                revert DynamicSwapFeeHookFailed();
            }
        } else {
            vars.swapFeePercentage = poolData.poolConfig.staticSwapFeePercentage;
        }

        // Non-reentrant call that updates accounting.
        // vars.amountCalculatedScaled18 is set inside of _swap. This is an unintuitive side-effect, but is done
        // to avoid stack too deep issues.
        (amountCalculated, amountIn, amountOut) = _swap(params, vars, poolData, vaultState);

        if (poolData.poolConfig.hooks.shouldCallAfterSwap) {
            // Adjust balances for the AfterSwap hook.
            (uint256 amountInScaled18, uint256 amountOutScaled18) = params.kind == SwapKind.EXACT_IN
                ? (vars.amountGivenScaled18, vars.amountCalculatedScaled18)
                : (vars.amountCalculatedScaled18, vars.amountGivenScaled18);
            if (
                IPoolHooks(params.pool).onAfterSwap(
                    IPoolHooks.AfterSwapParams({
                        kind: params.kind,
                        tokenIn: params.tokenIn,
                        tokenOut: params.tokenOut,
                        amountInScaled18: amountInScaled18,
                        amountOutScaled18: amountOutScaled18,
                        tokenInBalanceScaled18: poolData.balancesLiveScaled18[vars.indexIn],
                        tokenOutBalanceScaled18: poolData.balancesLiveScaled18[vars.indexOut],
                        sender: msg.sender,
                        userData: params.userData
                    }),
                    vars.amountCalculatedScaled18
                ) == false
            ) {
                revert AfterSwapHookFailed();
            }
        }
    }

    function _getSwapTokenIndexes(
        SwapParams memory params
    ) private view returns (uint256 indexIn, uint256 indexOut) {
        // Use the storage map only for translating token addresses to indices. Raw balances can be read from poolData.
        EnumerableMap.IERC20ToBytes32Map storage poolBalances = _poolTokenBalances[params.pool];

        // EnumerableMap stores indices *plus one* to use the zero index as a sentinel value for non-existence.
        indexIn = poolBalances.unchecked_indexOf(params.tokenIn);
        indexOut = poolBalances.unchecked_indexOf(params.tokenOut);

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
    }

    function _buildPoolSwapParams(
        SwapParams memory params,
        SwapVars memory vars,
        PoolData memory poolData
    ) internal view returns (IBasePool.PoolSwapParams memory) {
        return
            IBasePool.PoolSwapParams({
                kind: params.kind,
                amountGivenScaled18: vars.amountGivenScaled18,
                balancesScaled18: poolData.balancesLiveScaled18,
                indexIn: vars.indexIn,
                indexOut: vars.indexOut,
                sender: msg.sender,
                userData: params.userData
            });
    }

    /**
     * @dev Preconditions: decimalScalingFactors and tokenRates in `poolData` must be current.
     * Uses amountGivenRaw and kind from `params`.
     */
    function _computeAmountGivenScaled18(
        SwapVars memory vars,
        SwapParams memory params,
        PoolData memory poolData
    ) private pure returns (uint256) {
        // If the amountGiven is entering the pool math (ExactIn), round down, since a lower apparent amountIn leads
        // to a lower calculated amountOut, favoring the pool.
        return params.kind == SwapKind.EXACT_IN
            ? params.amountGivenRaw.toScaled18ApplyRateRoundDown(
                poolData.decimalScalingFactors[vars.indexIn],
                poolData.tokenRates[vars.indexIn]
            )
            : params.amountGivenRaw.toScaled18ApplyRateRoundUp(
                poolData.decimalScalingFactors[vars.indexOut],
                poolData.tokenRates[vars.indexOut]
            );
    }

    /**
     * @dev Main non-reentrant portion of the swap, which calls the pool hook and updates accounting. `vaultSwapParams`
     * are passed to the pool's `onSwap` hook.
     *
     * Preconditions: amountGivenScaled18, indexIn, indexOut in vars; decimalScalingFactors, tokenRates, poolConfig,
     *                balancesLiveScaled18 in `poolData`.
     * Side effects: mutates swapFeeAmountScaled18, amountCalculatedScaled18, protocolSwapFeeAmountRaw,
     *               creatorSwapFeeAmountRaw in vars; balancesRaw, balancesLiveScaled18 in `poolData`.
     * Updates `_protocolFees`, `_poolCreatorFees`, `_poolTokenBalances` in storage.
     * Emits Swap event. May emit ProtocolSwapFeeCharged, PoolCreatorSwapFeeCharged events.
     */
    function _swap(
        SwapParams memory params,
        SwapVars memory vars,
        PoolData memory poolData,
        VaultState memory vaultState
    ) internal nonReentrant returns (uint256 amountCalculatedRaw, uint256 amountInRaw, uint256 amountOutRaw) {
        // Perform the swap request hook and compute the new balances for 'token in' and 'token out' after the swap

        vars.amountCalculatedScaled18 = IBasePool(params.pool).onSwap(_buildPoolSwapParams(params, vars, poolData));

        // Note that balances are kept in memory, and are not fully computed until the `setPoolBalances` below.
        // Intervening code cannot read balances from storage, as they are temporarily out-of-sync here. This function
        // is nonReentrant, to guard against read-only reentrancy issues.

        // Set vars.swapFeeAmountScaled18 based on the amountCalculated.
        if (vars.swapFeePercentage > 0) {
            // Swap fee is always a percentage of the amountCalculated. On ExactIn, subtract it from the calculated
            // amountOut. On ExactOut, add it to the calculated amountIn.
            // Round up to avoid losses during precision loss.
            vars.swapFeeAmountScaled18 = vars.amountCalculatedScaled18.mulUp(vars.swapFeePercentage);
        }

        // (1) and (2): get raw amounts and check limits
        if (params.kind == SwapKind.EXACT_IN) {
            // Need to update `amountCalculatedScaled18` for the onAfterSwap hook.
            vars.amountCalculatedScaled18 -= vars.swapFeeAmountScaled18;

            // For `ExactIn` the amount calculated is leaving the Vault, so we round down.
            amountCalculatedRaw = vars.amountCalculatedScaled18.toRawUndoRateRoundDown(
                poolData.decimalScalingFactors[vars.indexOut],
                poolData.tokenRates[vars.indexOut]
            );

            (amountInRaw, amountOutRaw) = (params.amountGivenRaw, amountCalculatedRaw);

            if (amountOutRaw < params.limitRaw) {
                revert SwapLimit(amountOutRaw, params.limitRaw);
            }
        } else {
            vars.amountCalculatedScaled18 += vars.swapFeeAmountScaled18;

            // For `ExactOut` the amount calculated is entering the Vault, so we round up.
            amountCalculatedRaw = vars.amountCalculatedScaled18.toRawUndoRateRoundUp(
                poolData.decimalScalingFactors[vars.indexIn],
                poolData.tokenRates[vars.indexIn]
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
        (uint256 swapFeeIndex, IERC20 swapFeeToken) = params.kind == SwapKind.EXACT_IN
            ? (vars.indexOut, params.tokenOut)
            : (vars.indexIn, params.tokenIn);

        // Note that protocol fee storage is updated before balance storage, as the final raw balances need to take
        // the fees into account.
        (vars.protocolSwapFeeAmountRaw, vars.creatorSwapFeeAmountRaw) = _computeAndChargeProtocolAndCreatorSwapFees(
            poolData,
            vars.swapFeeAmountScaled18,
            vaultState.protocolSwapFeePercentage,
            params.pool,
            swapFeeToken,
            swapFeeIndex
        );

        {
            // stack-too-deep
            uint256 totalFees = (vars.protocolSwapFeeAmountRaw + vars.creatorSwapFeeAmountRaw);

            // 5) Pool balances: raw and live
            // Adjust for raw swap amounts and total fees on the calculated end.
            (uint256 newBalanceInRaw, uint256 newBalanceOutRaw) = params.kind == SwapKind.EXACT_IN
                ? (
                    poolData.balancesRaw[vars.indexIn] + amountInRaw,
                    poolData.balancesRaw[vars.indexOut] - amountOutRaw - totalFees
                )
                : (
                    poolData.balancesRaw[vars.indexIn] + amountInRaw - totalFees,
                    poolData.balancesRaw[vars.indexOut] - amountOutRaw
                );

            poolData.updateRawAndLiveBalance(vars.indexIn, newBalanceInRaw, Rounding.ROUND_DOWN);
            poolData.updateRawAndLiveBalance(vars.indexOut, newBalanceOutRaw, Rounding.ROUND_DOWN);
        }

        // 6) Store pool balances, raw and live
        _writePoolBalancesToStorage(params.pool, poolData);

        // 7) Off-chain events
        // Since the swapFeeAmountScaled18 (derived from scaling up either the amountGiven or amountCalculated)
        // also contains the rate, undo it when converting to raw.
        uint256 swapFeeAmountRaw = vars.swapFeeAmountScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[swapFeeIndex],
            poolData.tokenRates[swapFeeIndex]
        );

        emit Swap(
            params.pool,
            params.tokenIn,
            params.tokenOut,
            amountInRaw,
            amountOutRaw,
            vars.swapFeePercentage,
            swapFeeAmountRaw,
            swapFeeToken
        );
    }

    /*******************************************************************************
                                Pool Operations
    *******************************************************************************/

    /// @dev Avoid "stack too deep" - without polluting the Add/RemoveLiquidity params interface.
    struct LiquidityLocals {
        uint256 numTokens;
        uint256 protocolSwapFeeAmountRaw;
        uint256 creatorSwapFeeAmountRaw;
        uint256 tokenIndex;
    }

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

        VaultState memory vaultState = _ensureUnpausedAndGetVaultState(params.pool);

        // `_chargePendingYieldFeesUpdatePoolBalancesAndLoadPoolData` is non-reentrant, as it updates storage as well
        // as filling in poolData in memory. Since the add liquidity hooks are reentrant and could do anything,
        // including change these balances, we cannot defer settlement until `_addLiquidity`.
        //
        // Sets all fields in `poolData`. Side effects: updates `_poolTokenBalances`, `_protocolFees`,
        // `_poolCreatorFees` in storage. May emit ProtocolYieldFeeCharged and PoolCreatorYieldFeeCharged events.
        PoolData memory poolData = _chargePendingYieldFeesUpdatePoolBalancesAndLoadPoolData(
            params.pool,
            Rounding.ROUND_UP,
            vaultState.protocolYieldFeePercentage
        );
        InputHelpers.ensureInputLengthMatch(poolData.tokenConfig.length, params.maxAmountsIn.length);

        // Amounts are entering pool math, so round down.
        // Introducing amountsInScaled18 here and passing it through to _addLiquidity is not ideal,
        // but it avoids the even worse options of mutating amountsIn inside AddLiquidityParams,
        // or cluttering the AddLiquidityParams interface by adding amountsInScaled18.
        uint256[] memory maxAmountsInScaled18 = params.maxAmountsIn.copyToScaled18ApplyRateRoundDownArray(
            poolData.decimalScalingFactors,
            poolData.tokenRates
        );

        if (poolData.poolConfig.hooks.shouldCallBeforeAddLiquidity) {
            if (
                IPoolHooks(params.pool).onBeforeAddLiquidity(
                    params.to,
                    params.kind,
                    maxAmountsInScaled18,
                    params.minBptAmountOut,
                    poolData.balancesLiveScaled18,
                    params.userData
                ) == false
            ) {
                revert BeforeAddLiquidityHookFailed();
            }

            // The hook might alter the balances, so we need to read them again to ensure that the data is
            // fresh moving forward.
            // We also need to upscale (adding liquidity, so round up) again.
            poolData.reloadPossiblyStaleBalancesAndTokenRates(_poolTokenBalances[params.pool], Rounding.ROUND_UP);

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
            maxAmountsInScaled18,
            vaultState
        );

        if (poolData.poolConfig.hooks.shouldCallAfterAddLiquidity) {
            if (
                IPoolHooks(params.pool).onAfterAddLiquidity(
                    params.to,
                    amountsInScaled18,
                    bptAmountOut,
                    poolData.balancesLiveScaled18,
                    params.userData
                ) == false
            ) {
                revert AfterAddLiquidityHookFailed();
            }
        }
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
        uint256[] memory maxAmountsInScaled18,
        VaultState memory vaultState
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
        LiquidityLocals memory vars;
        vars.numTokens = poolData.tokenConfig.length;
        uint256[] memory swapFeeAmountsScaled18;

        if (params.kind == AddLiquidityKind.PROPORTIONAL) {
            bptAmountOut = params.minBptAmountOut;
            // Initializes the swapFeeAmountsScaled18 empty array (no swap fees on proportional add liquidity)
            swapFeeAmountsScaled18 = new uint256[](vars.numTokens);

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
            vars.tokenIndex = InputHelpers.getSingleInputIndex(maxAmountsInScaled18);

            amountsInScaled18 = maxAmountsInScaled18;
            (amountsInScaled18[vars.tokenIndex], swapFeeAmountsScaled18) = BasePoolMath
                .computeAddLiquiditySingleTokenExactOut(
                    poolData.balancesLiveScaled18,
                    vars.tokenIndex,
                    bptAmountOut,
                    _totalSupply(params.pool),
                    poolData.poolConfig.staticSwapFeePercentage,
                    IBasePool(params.pool).computeBalance
                );
        } else if (params.kind == AddLiquidityKind.CUSTOM) {
            poolData.poolConfig.requireAddCustomLiquidityEnabled();

            (amountsInScaled18, bptAmountOut, swapFeeAmountsScaled18, returnData) = IPoolLiquidity(params.pool)
                .onAddLiquidityCustom(
                    params.to,
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

        amountsInRaw = new uint256[](vars.numTokens);

        for (uint256 i = 0; i < vars.numTokens; ++i) {
            // 1) Calculate raw amount in.
            // amountsInRaw are amounts actually entering the Pool, so we round up.
            // Do not mutate in place yet, as we need them scaled for the `onAfterAddLiquidity` hook
            uint256 amountInRaw = amountsInScaled18[i].toRawUndoRateRoundUp(
                poolData.decimalScalingFactors[i],
                poolData.tokenRates[i]
            );
            amountsInRaw[i] = amountInRaw;

            {
                // stack-too-deep
                IERC20 token = poolData.tokenConfig[i].token;

                // 2) Check limits for raw amounts
                if (amountInRaw > params.maxAmountsIn[i]) {
                    revert AmountInAboveMax(token, amountInRaw, params.maxAmountsIn[i]);
                }

                // 3) Deltas: Debit of token[i] for amountInRaw
                _takeDebt(token, amountInRaw);

                // 4) Compute and charge protocol and creator fees.
                (vars.protocolSwapFeeAmountRaw, vars.creatorSwapFeeAmountRaw) = _computeAndChargeProtocolAndCreatorSwapFees(
                    poolData,
                    swapFeeAmountsScaled18[i],
                    vaultState.protocolSwapFeePercentage,
                    params.pool,
                    token,
                    i
                );
            }

             // 5) Pool balances: raw and live
            // We need regular balances to complete the accounting, and the upscaled balances
            // to use in the `after` hook later on.

            // A pool's token balance increases by amounts in after adding liquidity, minus fees.
            uint256 amountToIncreaseRaw = amountInRaw -
                vars.protocolSwapFeeAmountRaw -
                vars.creatorSwapFeeAmountRaw;

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

        // `_chargePendingYieldFeesUpdatePoolBalancesAndLoadPoolData` is non-reentrant, as it updates storage as well as filling in
        // poolData in memory. Since the remove liquidity hooks are reentrant and could do anything, including change
        // these balances, we cannot defer settlement until `_removeLiquidity`.
        //
        // Sets all fields in `poolData`. Side effects: updates `_poolTokenBalances`, `_protocolFees`,
        // `_poolCreatorFees` in storage. May emit ProtocolYieldFeeCharged and PoolCreatorYieldFeeCharged events.
        PoolData memory poolData = _chargePendingYieldFeesUpdatePoolBalancesAndLoadPoolData(
            params.pool,
            Rounding.ROUND_DOWN,
            vaultState.protocolYieldFeePercentage
        );
        InputHelpers.ensureInputLengthMatch(poolData.tokenConfig.length, params.minAmountsOut.length);

        // Amounts are entering pool math; higher amounts would burn more BPT, so round up to favor the pool.
        // Do not mutate minAmountsOut, so that we can directly compare the raw limits later, without potentially
        // losing precision by scaling up and then down.
        uint256[] memory minAmountsOutScaled18 = params.minAmountsOut.copyToScaled18ApplyRateRoundUpArray(
            poolData.decimalScalingFactors,
            poolData.tokenRates
        );

        if (poolData.poolConfig.hooks.shouldCallBeforeRemoveLiquidity) {
            if (
                IPoolHooks(params.pool).onBeforeRemoveLiquidity(
                    params.from,
                    params.kind,
                    params.maxBptAmountIn,
                    minAmountsOutScaled18,
                    poolData.balancesLiveScaled18,
                    params.userData
                ) == false
            ) {
                revert BeforeRemoveLiquidityHookFailed();
            }
            // The hook might alter the balances, so we need to read them again to ensure that the data is
            // fresh moving forward.
            // We also need to upscale (removing liquidity, so round down) again.
            poolData.reloadPossiblyStaleBalancesAndTokenRates(_poolTokenBalances[params.pool], Rounding.ROUND_DOWN);

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

        if (poolData.poolConfig.hooks.shouldCallAfterRemoveLiquidity) {
            if (
                IPoolHooks(params.pool).onAfterRemoveLiquidity(
                    params.from,
                    bptAmountIn,
                    amountsOutScaled18,
                    poolData.balancesLiveScaled18,
                    params.userData
                ) == false
            ) {
                revert AfterRemoveLiquidityHookFailed();
            }
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
        LiquidityLocals memory vars;
        vars.numTokens = poolData.tokenConfig.length;
        uint256[] memory swapFeeAmountsScaled18;

        if (params.kind == RemoveLiquidityKind.PROPORTIONAL) {
            bptAmountIn = params.maxBptAmountIn;
            swapFeeAmountsScaled18 = new uint256[](vars.numTokens);
            amountsOutScaled18 = BasePoolMath.computeProportionalAmountsOut(
                poolData.balancesLiveScaled18,
                _totalSupply(params.pool),
                bptAmountIn
            );
        } else if (params.kind == RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN) {
            poolData.poolConfig.requireUnbalancedLiquidityEnabled();
            bptAmountIn = params.maxBptAmountIn;
            amountsOutScaled18 = minAmountsOutScaled18;
            vars.tokenIndex = InputHelpers.getSingleInputIndex(params.minAmountsOut);

            (amountsOutScaled18[vars.tokenIndex], swapFeeAmountsScaled18) = BasePoolMath
                .computeRemoveLiquiditySingleTokenExactIn(
                    poolData.balancesLiveScaled18,
                    vars.tokenIndex,
                    bptAmountIn,
                    _totalSupply(params.pool),
                    poolData.poolConfig.staticSwapFeePercentage,
                    IBasePool(params.pool).computeBalance
                );
        } else if (params.kind == RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            poolData.poolConfig.requireUnbalancedLiquidityEnabled();
            amountsOutScaled18 = minAmountsOutScaled18;
            vars.tokenIndex = InputHelpers.getSingleInputIndex(params.minAmountsOut);

            (bptAmountIn, swapFeeAmountsScaled18) = BasePoolMath.computeRemoveLiquiditySingleTokenExactOut(
                poolData.balancesLiveScaled18,
                vars.tokenIndex,
                amountsOutScaled18[vars.tokenIndex],
                _totalSupply(params.pool),
                poolData.poolConfig.staticSwapFeePercentage,
                IBasePool(params.pool).computeInvariant
            );
        } else if (params.kind == RemoveLiquidityKind.CUSTOM) {
            poolData.poolConfig.requireRemoveCustomLiquidityEnabled();
            (bptAmountIn, amountsOutScaled18, swapFeeAmountsScaled18, returnData) = IPoolLiquidity(params.pool)
                .onRemoveLiquidityCustom(
                    params.from,
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

        amountsOutRaw = new uint256[](vars.numTokens);

        for (uint256 i = 0; i < vars.numTokens; ++i) {
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
                (vars.protocolSwapFeeAmountRaw, vars.creatorSwapFeeAmountRaw) = _computeAndChargeProtocolAndCreatorSwapFees(
                    poolData,
                    swapFeeAmountsScaled18[i],
                    vaultState.protocolSwapFeePercentage,
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
            uint256 amountToDecreaseRaw = amountOutRaw -
                vars.protocolSwapFeeAmountRaw -
                vars.creatorSwapFeeAmountRaw;

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
     * Side effects: updates `_protocolFees` and `_poolCreatorFees` storage (and emits events).
     * Should only be called in a non-reentrant context.
     * IMPORTANT: creator fees are calculated based on creatorAndLpFees, and not in totalFees. See example below
     * Example:
     * tokenOutAmount = 10000; poolSwapFeePerc = 10%; protocolFeePerc = 40%; creatorFeePerc = 60%
     * totalFees = tokenOutAmount * poolSwapFeePerc = 10000 * 10% = 1000
     * protocolFees = totalFees * protocolFeePerc = 1000 * 40% = 400
     * creatorAndLpFees = totalFees - protocolFees = 1000 - 400 = 600
     * creatorFees = creatorAndLpFees * creatorFeePerc = 600 * 60% = 360
     * lpFees (will stay in the pool) = creatorAndLpFees - creatorFees = 600 - 360 = 240
     */
    function _computeAndChargeProtocolAndCreatorSwapFees(
        PoolData memory poolData,
        uint256 swapFeeAmountScaled18,
        uint256 protocolSwapFeePercentage,
        address pool,
        IERC20 token,
        uint256 index
    ) internal returns (uint256 protocolSwapFeeAmountRaw, uint256 creatorSwapFeeAmountRaw) {
        // If swapFeeAmount equals zero no need to charge anything
        if (swapFeeAmountScaled18 > 0 && poolData.poolConfig.isPoolInRecoveryMode == false) {
            // Always charge fees on token. Store amount in native decimals.
            // Since the swapFeeAmountScaled18 also contains the rate, undo it when converting to raw.
            uint256 protocolSwapFeeAmountScaled18;
            uint256 creatorSwapFeeAmountScaled18;

            if (protocolSwapFeePercentage > 0) {
                protocolSwapFeeAmountScaled18 = swapFeeAmountScaled18.mulUp(protocolSwapFeePercentage);
                protocolSwapFeeAmountRaw = protocolSwapFeeAmountScaled18.toRawUndoRateRoundDown(
                    poolData.decimalScalingFactors[index],
                    poolData.tokenRates[index]
                );

                _protocolFees[pool][token] += protocolSwapFeeAmountRaw;
                emit ProtocolSwapFeeCharged(pool, address(token), protocolSwapFeeAmountRaw);
            }

            if (poolData.poolConfig.poolCreatorFeePercentage > 0) {
                creatorSwapFeeAmountScaled18 = (swapFeeAmountScaled18 - protocolSwapFeeAmountScaled18).mulUp(
                    poolData.poolConfig.poolCreatorFeePercentage
                );
                creatorSwapFeeAmountRaw = creatorSwapFeeAmountScaled18.toRawUndoRateRoundDown(
                    poolData.decimalScalingFactors[index],
                    poolData.tokenRates[index]
                );

                _poolCreatorFees[pool][token] += creatorSwapFeeAmountRaw;
                emit PoolCreatorSwapFeeCharged(pool, address(token), creatorSwapFeeAmountRaw);
            }

            // Ensure we can never charge more than the total swap fee.
            if (protocolSwapFeeAmountScaled18 + creatorSwapFeeAmountScaled18 > swapFeeAmountScaled18) {
                revert ProtocolFeesExceedSwapFee();
            }
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
