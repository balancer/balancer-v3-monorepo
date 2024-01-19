// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { Proxy } from "@openzeppelin/contracts/proxy/Proxy.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolCallbacks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolCallbacks.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";

import { PoolConfigBits, PoolConfigLib } from "./lib/PoolConfigLib.sol";
import { ERC20MultiToken } from "./token/ERC20MultiToken.sol";
import { VaultCommon } from "./VaultCommon.sol";

contract Vault is IVaultMain, VaultCommon, Proxy, ERC20MultiToken {
    using EnumerableMap for EnumerableMap.IERC20ToUint256Map;
    using InputHelpers for uint256;
    using FixedPoint for *;
    using ArrayHelpers for uint256[];
    using Address for *;
    using SafeERC20 for IERC20;
    using SafeCast for *;
    using PoolConfigLib for PoolConfig;
    using ScalingHelpers for *;

    constructor(
        IVaultExtension vaultExtension,
        IAuthorizer authorizer
    ) Authentication(bytes32(uint256(uint160(address(this))))) {
        _vaultExtension = vaultExtension;
        _authorizer = authorizer;

        _vaultPauseWindowEndTime = vaultExtension.getPauseWindowEndTime();
        _vaultBufferPeriodDuration = vaultExtension.getBufferPeriodDuration();
        _vaultBufferPeriodEndTime = vaultExtension.getBufferPeriodEndTime();
    }

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /**
     * @dev This modifier is used for functions that temporarily modify the `_tokenDeltas`
     * of the Vault but expect to revert or settle balances by the end of their execution.
     * It works by tracking the handlers involved in the execution and ensures that the
     * balances are properly settled by the time the last handler is executed.
     *
     * This is useful for functions like `invoke`, which performs arbitrary external calls:
     * we can keep track of temporary deltas changes, and make sure they are settled by the
     * time the external call is complete.
     */
    modifier transient() {
        // Add the current handler to the list
        _handlers.push(msg.sender);

        // The caller does everything here and has to settle all outstanding balances
        _;

        // Check if it's the last handler
        if (_handlers.length == 1) {
            // Ensure all balances are settled
            if (_nonzeroDeltaCount != 0) revert BalanceNotSettled();

            // Reset the handlers list
            delete _handlers;

            // Reset the counter
            delete _nonzeroDeltaCount;
        } else {
            // If it's not the last handler, simply remove it from the list
            _handlers.pop();
        }
    }

    /// @inheritdoc IVaultMain
    function invoke(bytes calldata data) external payable transient returns (bytes memory result) {
        // Executes the function call with value to the msg.sender.
        return (msg.sender).functionCallWithValue(data, msg.value);
    }

    /**
     * @dev This modifier ensures that the function it modifies can only be called
     * by the last handler in the `_handlers` array. This is used to enforce the
     * order of execution when multiple handlers are in play, ensuring only the
     * current or "active" handler can invoke certain operations in the Vault.
     * If no handler is found or the caller is not the expected handler,
     * it reverts the transaction with specific error messages.
     */
    modifier withHandler() {
        // If there are no handlers in the list, revert with an error.
        if (_handlers.length == 0) {
            revert NoHandler();
        }

        // Get the last handler from the `_handlers` array.
        // This represents the current active handler.
        address handler = _handlers[_handlers.length - 1];

        // If the current function caller is not the active handler, revert.
        if (msg.sender != handler) revert WrongHandler(msg.sender, handler);

        _;
    }

    /// @inheritdoc IVaultMain
    function settle(IERC20 token) public nonReentrant withHandler returns (uint256 paid) {
        uint256 reservesBefore = _tokenReserves[token];
        _tokenReserves[token] = token.balanceOf(address(this));
        paid = _tokenReserves[token] - reservesBefore;
        // subtraction must be safe
        _supplyCredit(token, paid, msg.sender);
    }

    /// @inheritdoc IVaultMain
    function wire(IERC20 token, address to, uint256 amount) public nonReentrant withHandler {
        // effects
        _takeDebt(token, amount, msg.sender);
        _tokenReserves[token] -= amount;
        // interactions
        token.safeTransfer(to, amount);
    }

    /// @inheritdoc IVaultMain
    function retrieve(IERC20 token, address from, uint256 amount) public nonReentrant withHandler onlyTrustedRouter {
        // effects
        _supplyCredit(token, amount, msg.sender);
        _tokenReserves[token] += amount;
        // interactions
        token.safeTransferFrom(from, address(this), amount);
    }

    /**
     * @notice Records the `debt` for a given handler and token.
     * @param token   The ERC20 token for which the `debt` will be accounted.
     * @param debt    The amount of `token` taken from the Vault in favor of the `handler`.
     * @param handler The account responsible for the debt.
     */
    function _takeDebt(IERC20 token, uint256 debt, address handler) internal {
        _accountDelta(token, debt.toInt256(), handler);
    }

    /**
     * @notice Records the `credit` for a given handler and token.
     * @param token   The ERC20 token for which the 'credit' will be accounted.
     * @param credit  The amount of `token` supplied to the Vault in favor of the `handler`.
     * @param handler The account credited with the amount.
     */
    function _supplyCredit(IERC20 token, uint256 credit, address handler) internal {
        _accountDelta(token, -credit.toInt256(), handler);
    }

    /**
     * @dev Accounts the delta for the given handler and token.
     * Positive delta represents debt, while negative delta represents surplus.
     * The function ensures that only the specified handler can update its respective delta.
     *
     * @param token   The ERC20 token for which the delta is being accounted.
     * @param delta   The difference in the token balance.
     *                Positive indicates a debit or a decrease in Vault's tokens,
     *                negative indicates a credit or an increase in Vault's tokens.
     * @param handler The handler whose balance difference is being accounted for.
     *                Must be the same as the caller of the function.
     */
    function _accountDelta(IERC20 token, int256 delta, address handler) internal {
        // If the delta is zero, there's nothing to account for.
        if (delta == 0) return;

        // Ensure that the handler specified is indeed the caller.
        if (handler != msg.sender) {
            revert WrongHandler(handler, msg.sender);
        }

        // Get the current recorded delta for this token and handler.
        int256 current = _tokenDeltas[handler][token];

        // Calculate the new delta after accounting for the change.
        int256 next = current + delta;

        unchecked {
            // If the resultant delta becomes zero after this operation,
            // decrease the count of non-zero deltas.
            if (next == 0) {
                _nonzeroDeltaCount--;
            }
            // If there was no previous delta (i.e., it was zero) and now we have one,
            // increase the count of non-zero deltas.
            else if (current == 0) {
                _nonzeroDeltaCount++;
            }
        }

        // Update the delta for this token and handler.
        _tokenDeltas[handler][token] = next;
    }

    /*******************************************************************************
                                    Pool Tokens
    *******************************************************************************/

    /// @inheritdoc IVaultMain
    function totalSupply(address token) external view returns (uint256) {
        return _totalSupply(token);
    }

    /// @inheritdoc IVaultMain
    function balanceOf(address token, address account) external view returns (uint256) {
        return _balanceOf(token, account);
    }

    /// @inheritdoc IVaultMain
    function allowance(address token, address owner, address spender) external view returns (uint256) {
        return _allowance(token, owner, spender);
    }

    /// @inheritdoc IVaultMain
    function transfer(address owner, address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, owner, to, amount);
        return true;
    }

    /// @inheritdoc IVaultMain
    function approve(address owner, address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, owner, spender, amount);
        return true;
    }

    /// @inheritdoc IVaultMain
    function transferFrom(address spender, address from, address to, uint256 amount) external returns (bool) {
        _spendAllowance(msg.sender, from, spender, amount);
        _transfer(msg.sender, from, to, amount);
        return true;
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

    struct SwapLocals {
        // Inline the shared struct fields vs. nesting, trading off verbosity for gas/memory/bytecode savings.
        uint256 indexIn;
        uint256 indexOut;
        uint256 tokenInBalance;
        uint256 tokenOutBalance;
        uint256 amountGivenScaled18;
        uint256 amountCalculatedScaled18;
        uint256 swapFeeAmountScaled18;
        uint256 swapFeePercentage;
        uint256 protocolSwapFeeAmountRaw;
        IBasePool.SwapParams poolSwapParams;
    }

    /// @inheritdoc IVaultMain
    function swap(
        SwapParams memory params
    )
        public
        withHandler
        withInitializedPool(params.pool)
        whenPoolNotPaused(params.pool)
        returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut)
    {
        if (params.amountGivenRaw == 0) {
            revert AmountGivenZero();
        }

        if (params.tokenIn == params.tokenOut) {
            revert CannotSwapSameToken();
        }

        PoolData memory poolData = _getPoolData(params.pool, Rounding.ROUND_DOWN);
        EnumerableMap.IERC20ToUint256Map storage poolBalances = _poolTokenBalances[params.pool];
        SwapLocals memory vars;

        // EnumerableMap stores indices *plus one* to use the zero index as a sentinel value for non-existence.
        vars.indexIn = poolBalances.unchecked_indexOf(params.tokenIn);
        vars.indexOut = poolBalances.unchecked_indexOf(params.tokenOut);

        // If either are zero, revert because the token wasn't registered to this pool.
        if (vars.indexIn == 0 || vars.indexOut == 0) {
            // We require the pool to be initialized, which means it's also registered.
            // This can only happen if the tokens are not registered.
            revert TokenNotRegistered();
        }

        // Convert to regular 0-based indices now, since we've established the tokens are valid.
        unchecked {
            vars.indexIn -= 1;
            vars.indexOut -= 1;
        }

        // We know from the above checks that `i` is a valid token index and can use `unchecked_valueAt`
        // to save storage reads.
        vars.tokenInBalance = poolBalances.unchecked_valueAt(vars.indexIn);
        vars.tokenOutBalance = poolBalances.unchecked_valueAt(vars.indexOut);

        // If the amountGiven is entering the pool math (GivenIn), round down, since a lower apparent amountIn leads
        // to a lower calculated amountOut, favoring the pool.
        vars.amountGivenScaled18 = params.kind == SwapKind.GIVEN_IN
            ? params.amountGivenRaw.toScaled18ApplyRateRoundDown(
                poolData.decimalScalingFactors[vars.indexIn],
                poolData.tokenRates[vars.indexIn]
            )
            : params.amountGivenRaw.toScaled18ApplyRateRoundUp(
                poolData.decimalScalingFactors[vars.indexOut],
                poolData.tokenRates[vars.indexOut]
            );

        vars.swapFeePercentage = _getSwapFeePercentage(poolData.config);

        if (vars.swapFeePercentage > 0 && params.kind == SwapKind.GIVEN_OUT) {
            // Round up to avoid losses during precision loss.
            vars.swapFeeAmountScaled18 =
                vars.amountGivenScaled18.divUp(vars.swapFeePercentage.complement()) -
                vars.amountGivenScaled18;
        }

        // Create the pool callback params (used for both beforeSwap, if required, and the main swap callbacks).
        // Function and inclusion in SwapLocals needed to avoid "stack too deep".
        vars.poolSwapParams = _buildSwapCallbackParams(params, vars, poolData);

        if (poolData.config.callbacks.shouldCallBeforeSwap) {
            if (IPoolCallbacks(params.pool).onBeforeSwap(vars.poolSwapParams) == false) {
                revert CallbackFailed();
            }

            _updatePoolDataLiveBalancesAndRates(params.pool, poolData, Rounding.ROUND_DOWN);
            // The call to _buildSwapCallbackParams also modifies poolSwapParams.balancesScaled18.
            // Set here again explicitly to avoid relying on a side effect.
            // TODO: ugliness necessitated by the stack issues; revisit on any refactor to see if this can be cleaner.
            vars.poolSwapParams.balancesScaled18 = poolData.balancesLiveScaled18;
        }

        (amountCalculated, amountIn, amountOut) = _swap(params, vars, poolData, poolBalances);

        if (poolData.config.callbacks.shouldCallAfterSwap) {
            // Adjust balances for the AfterSwap callback.
            (uint256 amountInScaled18, uint256 amountOutScaled18) = params.kind == SwapKind.GIVEN_IN
                ? (vars.amountGivenScaled18, vars.amountCalculatedScaled18)
                : (vars.amountCalculatedScaled18, vars.amountGivenScaled18);

            if (
                IPoolCallbacks(params.pool).onAfterSwap(
                    IPoolCallbacks.AfterSwapParams({
                        kind: params.kind,
                        tokenIn: params.tokenIn,
                        tokenOut: params.tokenOut,
                        amountInScaled18: amountInScaled18,
                        amountOutScaled18: amountOutScaled18,
                        tokenInBalanceScaled18: poolData.balancesLiveScaled18[vars.indexIn] + amountInScaled18,
                        tokenOutBalanceScaled18: poolData.balancesLiveScaled18[vars.indexOut] - amountOutScaled18,
                        sender: msg.sender,
                        userData: params.userData
                    }),
                    vars.amountCalculatedScaled18
                ) == false
            ) {
                revert CallbackFailed();
            }
        }

        // Swap fee is always deducted from tokenOut.
        // Since the swapFeeAmountScaled18 (derived from scaling up either the amountGiven or amountCalculated)
        // also contains the rate, undo it when converting to raw.
        uint256 swapFeeAmountRaw = vars.swapFeeAmountScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[vars.indexOut],
            poolData.tokenRates[vars.indexOut]
        );

        emit Swap(params.pool, params.tokenIn, params.tokenOut, amountIn, amountOut, swapFeeAmountRaw);
    }

    function _buildSwapCallbackParams(
        SwapParams memory params,
        SwapLocals memory vars,
        PoolData memory poolData
    ) private view returns (IBasePool.SwapParams memory) {
        return
            IBasePool.SwapParams({
                kind: params.kind,
                amountGivenScaled18: vars.amountGivenScaled18 + vars.swapFeeAmountScaled18,
                balancesScaled18: poolData.balancesLiveScaled18,
                indexIn: vars.indexIn,
                indexOut: vars.indexOut,
                sender: msg.sender,
                userData: params.userData
            });
    }

    /// @dev Non-reentrant portion of the swap, which calls the main callback and updates accounting.
    function _swap(
        SwapParams memory vaultSwapParams,
        SwapLocals memory vars,
        PoolData memory poolData,
        EnumerableMap.IERC20ToUint256Map storage poolBalances
    ) internal nonReentrant returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) {
        // Add swap fee to the amountGiven to account for the fee taken in GIVEN_OUT swap on tokenOut
        // Perform the swap request callback and compute the new balances for 'token in' and 'token out' after the swap
        // If it's a GivenIn swap, vars.swapFeeAmountScaled18 will be zero here, and set based on the amountCalculated.

        vars.amountCalculatedScaled18 = IBasePool(vaultSwapParams.pool).onSwap(vars.poolSwapParams);

        if (vars.swapFeePercentage > 0 && vaultSwapParams.kind == SwapKind.GIVEN_IN) {
            // Swap fee is a percentage of the amountCalculated for the GIVEN_IN swap
            // Round up to avoid losses during precision loss.
            vars.swapFeeAmountScaled18 = vars.amountCalculatedScaled18.mulUp(vars.swapFeePercentage);
            // Should subtract the fee from the amountCalculated for GIVEN_IN swap
            vars.amountCalculatedScaled18 -= vars.swapFeeAmountScaled18;
        }

        // For `GivenIn` the amount calculated is leaving the Vault, so we round down.
        // Round up when entering the Vault on `GivenOut`.
        amountCalculated = vaultSwapParams.kind == SwapKind.GIVEN_IN
            ? vars.amountCalculatedScaled18.toRawUndoRateRoundDown(
                poolData.decimalScalingFactors[vars.indexOut],
                poolData.tokenRates[vars.indexOut]
            )
            : vars.amountCalculatedScaled18.toRawUndoRateRoundUp(
                poolData.decimalScalingFactors[vars.indexIn],
                poolData.tokenRates[vars.indexIn]
            );

        (amountIn, amountOut) = vaultSwapParams.kind == SwapKind.GIVEN_IN
            ? (vaultSwapParams.amountGivenRaw, amountCalculated)
            : (amountCalculated, vaultSwapParams.amountGivenRaw);

        // Charge protocolSwapFee
        if (vars.swapFeeAmountScaled18 > 0 && _protocolSwapFeePercentage > 0) {
            // Always charge fees on tokenOut. Store amount in native decimals.
            // Since the swapFeeAmountScaled18 (derived from scaling up either the amountGiven or amountCalculated)
            // also contains the rate, undo it when converting to raw.
            vars.protocolSwapFeeAmountRaw = vars
                .swapFeeAmountScaled18
                .mulUp(_protocolSwapFeePercentage)
                .toRawUndoRateRoundDown(
                    poolData.decimalScalingFactors[vars.indexOut],
                    poolData.tokenRates[vars.indexOut]
                );

            _protocolSwapFees[vaultSwapParams.tokenOut] += vars.protocolSwapFeeAmountRaw;
        }

        // Use `unchecked_setAt` to save storage reads.
        poolBalances.unchecked_setAt(vars.indexIn, vars.tokenInBalance + amountIn);
        poolBalances.unchecked_setAt(vars.indexOut, vars.tokenOutBalance - amountOut - vars.protocolSwapFeeAmountRaw);

        // Account amountIn of tokenIn
        _takeDebt(vaultSwapParams.tokenIn, amountIn, msg.sender);
        // Account amountOut of tokenOut
        _supplyCredit(vaultSwapParams.tokenOut, amountOut, msg.sender);
    }

    /// @dev Returns swap fee for the pool.
    function _getSwapFeePercentage(PoolConfig memory config) internal pure returns (uint256) {
        if (config.hasDynamicSwapFee) {
            // TODO: Fetch dynamic swap fee from the pool using callback
            return 0;
        } else {
            return config.staticSwapFeePercentage;
        }
    }

    /*******************************************************************************
                            Pool Registration and Initialization
    *******************************************************************************/

    /// @inheritdoc IVaultMain
    function isPoolInitialized(address pool) external view returns (bool) {
        return _isPoolInitialized(pool);
    }

    /// @inheritdoc IVaultMain
    function getPoolConfig(address pool) external view returns (PoolConfig memory) {
        return _poolConfig[pool].toPoolConfig();
    }

    /// @inheritdoc IVaultMain
    function getPoolTokens(address pool) external view withRegisteredPool(pool) returns (IERC20[] memory) {
        return _getPoolTokens(pool);
    }

    /// @inheritdoc IVaultMain
    function getPoolTokenCountAndIndexOfToken(
        address pool,
        IERC20 token
    ) external view withRegisteredPool(pool) returns (uint256, uint256) {
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];
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

    /// @inheritdoc IVaultMain
    function getPoolTokenInfo(
        address pool
    )
        external
        view
        withRegisteredPool(pool)
        returns (
            IERC20[] memory tokens,
            TokenType[] memory tokenTypes,
            uint256[] memory balancesRaw,
            uint256[] memory decimalScalingFactors,
            IRateProvider[] memory rateProviders
        )
    {
        // Do not use _getPoolData, which makes external calls and could fail.
        (tokens, tokenTypes, balancesRaw, decimalScalingFactors, rateProviders, ) = _getPoolTokenInfo(pool);
    }

    /// @inheritdoc IVaultMain
    function getPoolTokenRates(address pool) external view withRegisteredPool(pool) returns (uint256[] memory) {
        return _getPoolTokenRates(pool);
    }

    /// @dev Reverts unless `pool` corresponds to an initialized Pool.
    modifier withInitializedPool(address pool) {
        _ensureInitializedPool(pool);
        _;
    }

    /// @dev Reverts unless `pool` corresponds to an initialized Pool.
    function _ensureInitializedPool(address pool) internal view {
        if (!_isPoolInitialized(pool)) {
            revert PoolNotInitialized(pool);
        }
    }

    /// @dev See `isPoolInitialized`
    function _isPoolInitialized(address pool) internal view returns (bool) {
        return _poolConfig[pool].isPoolInitialized();
    }

    /**
     * @notice Fetches the tokens and their corresponding balances for a given pool.
     * @dev Utilizes an enumerable map to obtain pool token balances.
     * The function is structured to minimize storage reads by leveraging the `unchecked_at` method.
     *
     * @param pool The address of the pool for which tokens and balances are to be fetched.
     * @return tokens An array of token addresses.
     */
    function _getPoolTokens(address pool) internal view returns (IERC20[] memory tokens) {
        // Retrieve the mapping of tokens and their balances for the specified pool.
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];

        // Initialize arrays to store tokens based on the number of tokens in the pool.
        tokens = new IERC20[](poolTokenBalances.length());

        for (uint256 i = 0; i < tokens.length; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length,
            // we can safely use `unchecked_at`. This ensures that `i` is a valid token index and minimizes
            // storage reads.
            (tokens[i], ) = poolTokenBalances.unchecked_at(i);
        }
    }

    /**
     * @dev Called by the external `getPoolTokenRates` function, and internally during pool operations,
     * this will make external calls for tokens that have rate providers.
     */
    function _getPoolTokenRates(address pool) internal view returns (uint256[] memory tokenRates) {
        // Retrieve the mapping of tokens for the specified pool.
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];
        mapping(IERC20 => TokenConfig) storage poolTokenConfig = _poolTokenConfig[pool];

        // Initialize arrays to store tokens based on the number of tokens in the pool.
        tokenRates = new uint256[](poolTokenBalances.length());
        IERC20 token;

        for (uint256 i = 0; i < tokenRates.length; ++i) {
            // Because the iteration is bounded by `tokenRates.length`, which matches the EnumerableMap's
            // length, we can safely use `unchecked_at`. This ensures that `i` is a valid token index and minimizes
            // storage reads.
            (token, ) = poolTokenBalances.unchecked_at(i);
            TokenType tokenType = poolTokenConfig[token].tokenType;

            if (tokenType == TokenType.STANDARD) {
                tokenRates[i] = FixedPoint.ONE;
            } else if (tokenType == TokenType.WITH_RATE) {
                tokenRates[i] = poolTokenConfig[token].rateProvider.getRate();
            } else {
                // TODO implement ERC4626 at a later stage.
                revert InvalidTokenConfiguration();
            }
        }
    }

    /**
     * @notice Fetches the balances for a given pool, with decimal and rate scaling factors applied.
     * @dev Utilizes an enumerable map to obtain pool tokens and raw balances.
     * The function is structured to minimize storage reads by leveraging the `unchecked_at` method.
     * It is typically called before or after liquidity operations.
     *
     * @param pool The address of the pool
     * @param poolData The corresponding poolData to be read and updated
     * @param roundingDirection Whether balance scaling should round up or down
     */
    function _updatePoolDataLiveBalancesAndRates(
        address pool,
        PoolData memory poolData,
        Rounding roundingDirection
    ) internal view {
        // Retrieve the mapping of tokens and their balances for the specified pool.
        // poolData already contains rawBalances, but they could be stale, so fetch from the Vault.
        // Likewise, the rates could also have changed.
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];
        mapping(IERC20 => TokenConfig) storage poolTokenConfig = _poolTokenConfig[pool];
        uint256 numTokens = poolTokenBalances.length();
        uint256 balanceRaw;
        IERC20 token;

        for (uint256 i = 0; i < numTokens; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length,
            // we can safely use `unchecked_at`. This ensures that `i` is a valid token index and minimizes
            // storage reads.
            (token, balanceRaw) = poolTokenBalances.unchecked_at(i);
            TokenType tokenType = poolTokenConfig[token].tokenType;

            if (tokenType == TokenType.STANDARD) {
                poolData.tokenRates[i] = FixedPoint.ONE;
            } else if (tokenType == TokenType.WITH_RATE) {
                // TODO Adjust for protocol fees?
                poolData.tokenRates[i] = poolTokenConfig[token].rateProvider.getRate();
            } else {
                // TODO implement ERC4626 at a later stage.
                revert InvalidTokenConfiguration();
            }

            poolData.balancesLiveScaled18[i] = roundingDirection == Rounding.ROUND_UP
                ? balanceRaw.toScaled18ApplyRateRoundUp(poolData.decimalScalingFactors[i], poolData.tokenRates[i])
                : balanceRaw.toScaled18ApplyRateRoundDown(poolData.decimalScalingFactors[i], poolData.tokenRates[i]);
        }
    }

    function _getPoolTokenInfo(
        address pool
    )
        internal
        view
        returns (
            IERC20[] memory tokens,
            TokenType[] memory tokenTypes,
            uint256[] memory balancesRaw,
            uint256[] memory decimalScalingFactors,
            IRateProvider[] memory rateProviders,
            PoolConfig memory poolConfig
        )
    {
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];
        mapping(IERC20 => TokenConfig) storage poolTokenConfig = _poolTokenConfig[pool];

        uint256 numTokens = poolTokenBalances.length();
        poolConfig = _poolConfig[pool].toPoolConfig();

        tokens = new IERC20[](numTokens);
        tokenTypes = new TokenType[](numTokens);
        balancesRaw = new uint256[](numTokens);
        rateProviders = new IRateProvider[](numTokens);
        decimalScalingFactors = PoolConfigLib.getDecimalScalingFactors(poolConfig, numTokens);
        IERC20 token;

        for (uint256 i = 0; i < numTokens; i++) {
            (token, balancesRaw[i]) = poolTokenBalances.unchecked_at(i);
            tokens[i] = token;
            rateProviders[i] = poolTokenConfig[token].rateProvider;
            tokenTypes[i] = poolTokenConfig[token].tokenType;
        }
    }

    function _getPoolData(address pool, Rounding roundingDirection) internal view returns (PoolData memory poolData) {
        (
            poolData.tokens,
            poolData.tokenTypes,
            poolData.balancesRaw,
            poolData.decimalScalingFactors,
            poolData.rateProviders,
            poolData.config
        ) = _getPoolTokenInfo(pool);

        uint256 numTokens = poolData.tokens.length;

        // Initialize arrays to store balances and rates based on the number of tokens in the pool.
        // Will be read raw, then upscaled and rounded as directed.
        poolData.balancesLiveScaled18 = new uint256[](numTokens);
        poolData.tokenRates = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            TokenType tokenType = poolData.tokenTypes[i];

            if (tokenType == TokenType.STANDARD) {
                poolData.tokenRates[i] = FixedPoint.ONE;
            } else if (tokenType == TokenType.WITH_RATE) {
                poolData.tokenRates[i] = poolData.rateProviders[i].getRate();
            } else {
                // TODO implement ERC4626 at a later stage. Not coming from user input, so can only be these three.
                revert InvalidTokenConfiguration();
            }

            //TODO: remove pending yield fee using live balance mechanism
            poolData.balancesLiveScaled18[i] = roundingDirection == Rounding.ROUND_UP
                ? poolData.balancesRaw[i].toScaled18ApplyRateRoundUp(
                    poolData.decimalScalingFactors[i],
                    poolData.tokenRates[i]
                )
                : poolData.balancesRaw[i].toScaled18ApplyRateRoundDown(
                    poolData.decimalScalingFactors[i],
                    poolData.tokenRates[i]
                );
        }
    }

    /*******************************************************************************
                                Pool Operations
    *******************************************************************************/

    /// @dev Rejects routers not approved by governance and users
    modifier onlyTrustedRouter() {
        _onlyTrustedRouter(msg.sender);
        _;
    }

    /// @inheritdoc IVaultMain
    function initialize(
        address pool,
        address to,
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external withHandler withRegisteredPool(pool) whenPoolNotPaused(pool) returns (uint256 bptAmountOut) {
        PoolData memory poolData = _getPoolData(pool, Rounding.ROUND_DOWN);

        if (poolData.config.isPoolInitialized) {
            revert PoolAlreadyInitialized(pool);
        }

        InputHelpers.ensureInputLengthMatch(poolData.tokens.length, exactAmountsIn.length);

        // Amounts are entering pool math, so round down. A lower invariant after the join means less bptOut,
        // favoring the pool.
        uint256[] memory exactAmountsInScaled18 = exactAmountsIn.copyToScaled18ApplyRateRoundDownArray(
            poolData.decimalScalingFactors,
            poolData.tokenRates
        );

        if (poolData.config.callbacks.shouldCallBeforeInitialize) {
            if (IPoolCallbacks(pool).onBeforeInitialize(exactAmountsInScaled18, userData) == false) {
                revert CallbackFailed();
            }
        }

        bptAmountOut = _initialize(pool, to, poolData, tokens, exactAmountsIn, exactAmountsInScaled18, minBptAmountOut);

        if (poolData.config.callbacks.shouldCallAfterInitialize) {
            if (IPoolCallbacks(pool).onAfterInitialize(exactAmountsInScaled18, bptAmountOut, userData) == false) {
                revert CallbackFailed();
            }
        }
    }

    function _initialize(
        address pool,
        address to,
        PoolData memory poolData,
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        uint256[] memory exactAmountsInScaled18,
        uint256 minBptAmountOut
    ) internal nonReentrant returns (uint256 bptAmountOut) {
        for (uint256 i = 0; i < poolData.tokens.length; ++i) {
            IERC20 actualToken = poolData.tokens[i];

            // Tokens passed into `initialize` are the "expected" tokens.
            if (actualToken != tokens[i]) {
                revert TokensMismatch(pool, address(tokens[i]), address(actualToken));
            }

            // Debit of token[i] for amountIn
            _takeDebt(actualToken, exactAmountsIn[i], msg.sender);
        }

        // Store the new Pool balances.
        _setPoolBalances(pool, exactAmountsIn);
        emit PoolBalanceChanged(pool, to, poolData.tokens, exactAmountsIn.unsafeCastToInt256(true));

        // Store config and mark the pool as initialized
        poolData.config.isPoolInitialized = true;
        _poolConfig[pool] = poolData.config.fromPoolConfig();

        // Pass scaled balances to the pool
        bptAmountOut = IBasePool(pool).computeInvariant(exactAmountsInScaled18);

        _ensureMinimumTotalSupply(bptAmountOut);

        // At this point we know that bptAmountOut >= _MINIMUM_TOTAL_SUPPLY, so this will not revert.
        bptAmountOut -= _MINIMUM_TOTAL_SUPPLY;
        // When adding liquidity, we must mint tokens concurrently with updating pool balances,
        // as the pool's math relies on totalSupply.
        // Minting will be reverted if it results in a total supply less than the _MINIMUM_TOTAL_SUPPLY.
        _mintMinimumSupplyReserve(address(pool));
        _mint(address(pool), to, bptAmountOut);

        // At this point we have the calculated BPT amount.
        if (bptAmountOut < minBptAmountOut) {
            revert BptAmountOutBelowMin(bptAmountOut, minBptAmountOut);
        }

        // Emit an event to log the pool initialization
        emit PoolInitialized(pool);
    }

    /// @inheritdoc IVaultMain
    function addLiquidity(
        AddLiquidityParams memory params
    )
        external
        withHandler
        withInitializedPool(params.pool)
        whenPoolNotPaused(params.pool)
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData)
    {
        // Round balances up when adding liquidity:
        // If proportional, higher balances = higher proportional amountsIn, favoring the pool.
        // If unbalanced, higher balances = lower invariant ratio with fees.
        // bptOut = supply * (ratio - 1), so lower ratio = less bptOut, favoring the pool.
        PoolData memory poolData = _getPoolData(params.pool, Rounding.ROUND_UP);
        InputHelpers.ensureInputLengthMatch(poolData.tokens.length, params.maxAmountsIn.length);

        // Amounts are entering pool math, so round down.
        // Introducing amountsInScaled18 here and passing it through to _addLiquidity is not ideal,
        // but it avoids the even worse options of mutating amountsIn inside AddLiquidityParams,
        // or cluttering the AddLiquidityParams interface by adding amountsInScaled18.
        uint256[] memory maxAmountsInScaled18 = params.maxAmountsIn.copyToScaled18ApplyRateRoundDownArray(
            poolData.decimalScalingFactors,
            poolData.tokenRates
        );

        if (poolData.config.callbacks.shouldCallBeforeAddLiquidity) {
            // TODO: check if `before` needs kind.
            if (
                IPoolCallbacks(params.pool).onBeforeAddLiquidity(
                    params.to,
                    maxAmountsInScaled18,
                    params.minBptAmountOut,
                    poolData.balancesLiveScaled18,
                    params.userData
                ) == false
            ) {
                revert CallbackFailed();
            }

            // The callback might alter the balances, so we need to read them again to ensure that the data is
            // fresh moving forward.
            // We also need to upscale (adding liquidity, so round up) again.
            _updatePoolDataLiveBalancesAndRates(params.pool, poolData, Rounding.ROUND_UP);
        }

        // The bulk of the work is done here: the corresponding Pool callback is invoked and its final balances
        // are computed. This function is non-reentrant, as it performs the accounting updates.
        // Note that poolData is mutated to update the Raw and Live balances, so they are accurate when passed
        // into the AfterAddLiquidity callback.
        // `amountsInScaled18` will be overwritten in the custom case, so we need to pass it back and forth to
        // encapsulate that logic in `_addLiquidity`.
        uint256[] memory amountsInScaled18;
        (amountsIn, amountsInScaled18, bptAmountOut, returnData) = _addLiquidity(
            poolData,
            params,
            maxAmountsInScaled18
        );

        if (poolData.config.callbacks.shouldCallAfterAddLiquidity) {
            if (
                IPoolCallbacks(params.pool).onAfterAddLiquidity(
                    params.to,
                    amountsInScaled18,
                    bptAmountOut,
                    poolData.balancesLiveScaled18,
                    params.userData
                ) == false
            ) {
                revert CallbackFailed();
            }
        }
    }

    /**
     * @dev Calls the appropriate pool callback and calculates the required inputs and outputs for the operation
     * considering the given kind, and updates the vault's internal accounting. This includes:
     * - Setting pool balances
     * - Taking debt from the liquidity provider
     * - Minting pool tokens
     * - Emitting events
     *
     * It is non-reentrant, as it performs external calls and updates the vault's state accordingly. This is the only
     * place where the state is updated within `addLiquidity`.
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
        if (params.kind == AddLiquidityKind.UNBALANCED) {
            amountsInScaled18 = maxAmountsInScaled18;
            bptAmountOut = BasePoolMath.computeAddLiquidityUnbalanced(
                poolData.balancesLiveScaled18,
                maxAmountsInScaled18,
                _totalSupply(params.pool),
                _getSwapFeePercentage(poolData.config),
                IBasePool(params.pool).computeInvariant
            );
        } else if (params.kind == AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            bptAmountOut = params.minBptAmountOut;
            uint256 tokenIndex = InputHelpers.getSingleInputIndex(maxAmountsInScaled18);

            amountsInScaled18 = maxAmountsInScaled18;
            amountsInScaled18[tokenIndex] = BasePoolMath.computeAddLiquiditySingleTokenExactOut(
                poolData.balancesLiveScaled18,
                tokenIndex,
                bptAmountOut,
                _totalSupply(params.pool),
                _getSwapFeePercentage(poolData.config),
                IBasePool(params.pool).computeBalance
            );
        } else if (params.kind == AddLiquidityKind.CUSTOM) {
            _poolConfig[params.pool].requireSupportsAddLiquidityCustom();

            (amountsInScaled18, bptAmountOut, returnData) = IPoolLiquidity(params.pool).onAddLiquidityCustom(
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

        // TODO: enforce min and max.
        uint256 numTokens = poolData.tokens.length;
        amountsInRaw = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            // amountsInRaw are amounts actually entering the Pool, so we round up.
            // Do not mutate in place yet, as we need them scaled for the `onAfterAddLiquidity` callback
            uint256 amountInRaw = amountsInScaled18[i].toRawUndoRateRoundUp(
                poolData.decimalScalingFactors[i],
                poolData.tokenRates[i]
            );

            // The limits must be checked for raw amounts
            if (amountInRaw > params.maxAmountsIn[i]) {
                revert AmountInAboveMax(poolData.tokens[i], amountInRaw, params.maxAmountsIn[i]);
            }

            // Debit of token[i] for amountInRaw
            _takeDebt(poolData.tokens[i], amountInRaw, msg.sender);

            // We need regular balances to complete the accounting, and the upscaled balances
            // to use in the `after` callback later on.
            poolData.balancesRaw[i] += amountInRaw;
            poolData.balancesLiveScaled18[i] += amountsInScaled18[i];

            amountsInRaw[i] = amountInRaw;
        }

        // Store the new pool balances.
        _setPoolBalances(params.pool, poolData.balancesRaw);

        // When adding liquidity, we must mint tokens concurrently with updating pool balances,
        // as the pool's math relies on totalSupply.
        _mint(address(params.pool), params.to, bptAmountOut);

        emit PoolBalanceChanged(params.pool, params.to, poolData.tokens, amountsInRaw.unsafeCastToInt256(true));
    }

    /// @inheritdoc IVaultMain
    function removeLiquidity(
        RemoveLiquidityParams memory params
    )
        external
        withInitializedPool(params.pool)
        whenPoolNotPaused(params.pool)
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData)
    {
        // Round down when removing liquidity:
        // If proportional, lower balances = lower proportional amountsOut, favoring the pool.
        // If unbalanced, lower balances = lower invariant ratio without fees.
        // bptIn = supply * (1 - ratio), so lower ratio = more bptIn, favoring the pool.
        PoolData memory poolData = _getPoolData(params.pool, Rounding.ROUND_DOWN);
        InputHelpers.ensureInputLengthMatch(poolData.tokens.length, params.minAmountsOut.length);

        // Amounts are entering pool math; higher amounts would burn more BPT, so round up to favor the pool.
        // Do not mutate minAmountsOut, so that we can directly compare the raw limits later, without potentially
        // losing precision by scaling up and then down.
        uint256[] memory minAmountsOutScaled18 = params.minAmountsOut.copyToScaled18ApplyRateRoundUpArray(
            poolData.decimalScalingFactors,
            poolData.tokenRates
        );

        if (poolData.config.callbacks.shouldCallBeforeRemoveLiquidity) {
            // TODO: check if `before` callback needs kind.
            if (
                IPoolCallbacks(params.pool).onBeforeRemoveLiquidity(
                    params.from,
                    params.maxBptAmountIn,
                    minAmountsOutScaled18,
                    poolData.balancesLiveScaled18,
                    params.userData
                ) == false
            ) {
                revert CallbackFailed();
            }
            // The callback might alter the balances, so we need to read them again to ensure that the data is
            // fresh moving forward.
            // We also need to upscale (removing liquidity, so round down) again.
            _updatePoolDataLiveBalancesAndRates(params.pool, poolData, Rounding.ROUND_DOWN);
        }

        // The bulk of the work is done here: the corresponding Pool callback is invoked, and its final balances
        // are computed. This function is non-reentrant, as it performs the accounting updates.
        // Note that poolData is mutated to update the Raw and Live balances, so they are accurate when passed
        // into the AfterRemoveLiquidity callback.
        uint256[] memory amountsOutScaled18;
        (bptAmountIn, amountsOut, amountsOutScaled18, returnData) = _removeLiquidity(
            poolData,
            params,
            minAmountsOutScaled18
        );

        if (poolData.config.callbacks.shouldCallAfterRemoveLiquidity) {
            if (
                IPoolCallbacks(params.pool).onAfterRemoveLiquidity(
                    params.from,
                    bptAmountIn,
                    amountsOutScaled18,
                    poolData.balancesLiveScaled18,
                    params.userData
                ) == false
            ) {
                revert CallbackFailed();
            }
        }
    }

    /// @inheritdoc IVaultMain
    function removeLiquidityRecovery(
        address pool,
        address from,
        uint256 exactBptAmountIn
    )
        external
        nonReentrant
        withInitializedPool(pool)
        onlyInRecoveryMode(pool)
        returns (uint256[] memory amountsOutRaw)
    {
        // Retrieve the mapping of tokens and their balances for the specified pool.
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];
        uint256 numTokens = poolTokenBalances.length();

        // Initialize arrays to store tokens and balances based on the number of tokens in the pool.
        IERC20[] memory tokens = new IERC20[](numTokens);
        uint256[] memory balancesRaw = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length,
            // we can safely use `unchecked_at`. This ensures that `i` is a valid token index and minimizes
            // storage reads.
            (tokens[i], balancesRaw[i]) = poolTokenBalances.unchecked_at(i);
        }

        amountsOutRaw = BasePoolMath.computeProportionalAmountsOut(balancesRaw, _totalSupply(pool), exactBptAmountIn);

        _removeLiquidityUpdateAccounting(pool, from, tokens, balancesRaw, exactBptAmountIn, amountsOutRaw);
    }

    /**
     * @dev Calls the appropriate pool callback and calculates the required inputs and outputs for the operation
     * considering the given kind, and updates the vault's internal accounting. This includes:
     * - Setting pool balances
     * - Supplying credit to the liquidity provider
     * - Burning pool tokens
     * - Emitting events
     *
     * It is non-reentrant, as it performs external calls and updates the vault's state accordingly. This is the only
     * place where the state is updated within `removeLiquidity`.
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
        uint256 tokenOutIndex;

        if (params.kind == RemoveLiquidityKind.PROPORTIONAL) {
            bptAmountIn = params.maxBptAmountIn;
            amountsOutScaled18 = BasePoolMath.computeProportionalAmountsOut(
                poolData.balancesLiveScaled18,
                _totalSupply(params.pool),
                bptAmountIn
            );
        } else if (params.kind == RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN) {
            bptAmountIn = params.maxBptAmountIn;

            amountsOutScaled18 = minAmountsOutScaled18;
            tokenOutIndex = InputHelpers.getSingleInputIndex(params.minAmountsOut);
            amountsOutScaled18[tokenOutIndex] = BasePoolMath.computeRemoveLiquiditySingleTokenExactIn(
                poolData.balancesLiveScaled18,
                tokenOutIndex,
                bptAmountIn,
                _totalSupply(params.pool),
                _getSwapFeePercentage(poolData.config),
                IBasePool(params.pool).computeBalance
            );
        } else if (params.kind == RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            amountsOutScaled18 = minAmountsOutScaled18;
            tokenOutIndex = InputHelpers.getSingleInputIndex(params.minAmountsOut);

            bptAmountIn = BasePoolMath.computeRemoveLiquiditySingleTokenExactOut(
                poolData.balancesLiveScaled18,
                tokenOutIndex,
                amountsOutScaled18[tokenOutIndex],
                _totalSupply(params.pool),
                _getSwapFeePercentage(poolData.config),
                IBasePool(params.pool).computeInvariant
            );
        } else if (params.kind == RemoveLiquidityKind.CUSTOM) {
            (bptAmountIn, amountsOutScaled18, returnData) = IPoolLiquidity(params.pool).onRemoveLiquidityCustom(
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

        uint256 numTokens = poolData.tokens.length;
        amountsOutRaw = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            // Note that poolData.balancesRaw will also be updated in `_removeLiquidityUpdateAccounting`
            poolData.balancesLiveScaled18[i] -= amountsOutScaled18[i];

            // amountsOut are amounts exiting the Pool, so we round down.
            amountsOutRaw[i] = amountsOutScaled18[i].toRawUndoRateRoundDown(
                poolData.decimalScalingFactors[i],
                poolData.tokenRates[i]
            );

            if (amountsOutRaw[i] < params.minAmountsOut[i]) {
                revert AmountOutBelowMin(poolData.tokens[i], amountsOutRaw[i], params.minAmountsOut[i]);
            }
        }

        _removeLiquidityUpdateAccounting(
            params.pool,
            params.from,
            poolData.tokens,
            poolData.balancesRaw,
            bptAmountIn,
            amountsOutRaw
        );
    }

    /**
     * @dev Updates the vault's accounting within a `removeLiquidity` operation. This includes:
     * - Setting pool balances
     * - Supplying credit to the liquidity provider
     * - Burning pool tokens
     * - Emitting events
     *
     * This function also supports queries as a special case, where the pool tokens from the sender are not required.
     * It must be called in a non-reentrant context.
     */
    function _removeLiquidityUpdateAccounting(
        address pool,
        address from,
        IERC20[] memory tokens,
        uint256[] memory balancesRaw,
        uint256 bptAmountIn,
        uint256[] memory amountsOutRaw
    ) internal {
        for (uint256 i = 0; i < tokens.length; ++i) {
            // Credit token[i] for amountOut
            _supplyCredit(tokens[i], amountsOutRaw[i], msg.sender);

            // Compute the new Pool balances. A Pool's token balance always decreases after an exit (potentially by 0).
            balancesRaw[i] -= amountsOutRaw[i];
        }

        // Store the new pool balances.
        _setPoolBalances(pool, balancesRaw);

        // Trusted routers use Vault's allowances, which are infinite anyways for pool tokens.
        if (!_isTrustedRouter(msg.sender)) {
            _spendAllowance(address(pool), from, msg.sender, bptAmountIn);
        }

        if (!_isQueryDisabled && EVMCallModeHelpers.isStaticCall()) {
            // Increase `from` balance to ensure the burn function succeeds.
            _queryModeBalanceIncrease(pool, from, bptAmountIn);
        }
        // When removing liquidity, we must burn tokens concurrently with updating pool balances,
        // as the pool's math relies on totalSupply.
        // Burning will be reverted if it results in a total supply less than the _MINIMUM_TOTAL_SUPPLY.
        _burn(address(pool), from, bptAmountIn);

        emit PoolBalanceChanged(
            pool,
            from,
            tokens,
            // We can unsafely cast to int256 because balances are actually stored as uint112
            // TODO No they aren't anymore (stored as uint112)! Review this.
            amountsOutRaw.unsafeCastToInt256(false)
        );
    }

    /**
     * @dev Sets the balances of a Pool's tokens to `newBalances`.
     *
     * WARNING: this assumes `newBalances` has the same length and order as the Pool's tokens.
     */
    function _setPoolBalances(address pool, uint256[] memory newBalances) internal {
        EnumerableMap.IERC20ToUint256Map storage poolBalances = _poolTokenBalances[pool];

        for (uint256 i = 0; i < newBalances.length; ++i) {
            // Since we assume all newBalances are properly ordered, we can simply use `unchecked_setAt`
            // to avoid one less storage read per token.
            poolBalances.unchecked_setAt(i, newBalances[i]);
        }
    }

    function _onlyTrustedRouter(address sender) internal pure {
        if (!_isTrustedRouter(sender)) {
            revert RouterNotTrusted();
        }
    }

    function _isTrustedRouter(address) internal pure returns (bool) {
        //TODO: Implement based on approval by governance and user
        return true;
    }

    /*******************************************************************************
                                    Authentication
    *******************************************************************************/

    /// @inheritdoc IVaultMain
    function getAuthorizer() external view returns (IAuthorizer) {
        return _authorizer;
    }

    /// @inheritdoc IVaultMain
    function setAuthorizer(IAuthorizer newAuthorizer) external nonReentrant authenticate {
        _authorizer = newAuthorizer;

        emit AuthorizerChanged(newAuthorizer);
    }

    /// @dev Access control is delegated to the Authorizer
    function _canPerform(bytes32 actionId, address user) internal view override returns (bool) {
        return _authorizer.canPerform(actionId, user, address(this));
    }

    /*******************************************************************************
                                     Default handlers
    *******************************************************************************/

    receive() external payable {
        revert CannotReceiveEth();
    }

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
