// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

// solhint-disable-next-line max-line-length
import { IVault, PoolConfig, PoolCallbacks, LiquidityManagement } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";

import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { Asset, AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import { ERC20MultiToken } from "@balancer-labs/v3-solidity-utils/contracts/token/ERC20MultiToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";

import { PoolConfigBits, PoolConfigLib } from "./lib/PoolConfigLib.sol";

contract Vault is IVault, Authentication, ERC20MultiToken, ReentrancyGuard {
    using EnumerableMap for EnumerableMap.IERC20ToUint256Map;
    using InputHelpers for uint256;
    using FixedPoint for *;
    using AssetHelpers for *;
    using ArrayHelpers for uint256[];
    using Address for *;
    using SafeERC20 for IERC20;
    using SafeCast for *;
    using PoolConfigLib for PoolConfig;
    using PoolConfigLib for PoolCallbacks;
    using ScalingHelpers for *;

    // Minimum BPT amount minted upon initialization.
    uint256 private constant _MINIMUM_BPT = 1e6;

    // Pools can have two, three, or four tokens.
    uint256 private constant _MIN_TOKENS = 2;
    // This maximum token count is also hard-coded in `PoolConfigLib`.
    uint256 private constant _MAX_TOKENS = 4;

    // 1e18 corresponds to a 100% fee.
    uint256 private constant _MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50e16; // 50%

    // 1e18 corresponds to a 100% fee.
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 10e16; // 10%

    // Registry of pool configs.
    mapping(address => PoolConfigBits) internal _poolConfig;

    // Store pool pause managers.
    mapping(address => address) internal _poolPauseManagers;

    // Pool -> (token -> balance): Pool's ERC20 tokens balances stored at the Vault.
    mapping(address => EnumerableMap.IERC20ToUint256Map) internal _poolTokenBalances;

    /// @notice List of handlers. It is non-empty only during `invoke` calls.
    address[] private _handlers;

    /**
     * @notice The total number of nonzero deltas over all active + completed lockers.
     * @dev It is non-zero only during `invoke` calls.
     */
    uint256 private _nonzeroDeltaCount;

    /**
     * @notice Represents the asset due/owed to each handler.
     * @dev Must all net to zero when the last handler is released.
     */
    mapping(address => mapping(IERC20 => int256)) private _tokenDeltas;

    /**
     * @notice Represents the total reserve of each ERC20 token.
     * @dev It should be always equal to `token.balanceOf(vault)`, except during `invoke`.
     */
    mapping(IERC20 => uint256) private _tokenReserves;

    // We allow 0% swap fee.
    // The protocol swap fee is charged whenever a swap occurs, as a percentage of the fee charged by the Pool.
    // TODO consider using uint64 and packing with other things (when we have other things).
    uint256 private _protocolSwapFeePercentage;

    // Token -> fee: Protocol's swap fees accumulated in the Vault for harvest.
    mapping(IERC20 => uint256) private _protocolSwapFees;

    // Upgradeable contract in charge of setting permissions.
    IAuthorizer private _authorizer;

    /// @notice If set to true, disables query functionality of the Vault. Can be modified only by governance.
    bool private _isQueryDisabled;

    uint256 public constant MAX_PAUSE_WINDOW_DURATION = 356 days * 4;
    uint256 public constant MAX_BUFFER_PERIOD_DURATION = 90 days;

    // The Pause Window and Buffer Period are timestamp-based: they should not be relied upon for sub-minute accuracy.
    // solhint-disable not-rely-on-time

    uint256 internal immutable _vaultPauseWindowEndTime;
    uint256 internal immutable _vaultBufferPeriodEndTime;
    // Stored as a convenience, to avoid calculating it on every operation.
    uint256 internal immutable _vaultBufferPeriodDuration;

    bool private _vaultPaused;

    /// @dev Modifier to make a function callable only when the Vault is not paused.
    modifier whenVaultNotPaused() {
        _ensureVaultNotPaused();
        _;
    }

    /// @dev Modifier to make a function callable only when the Vault and Pool are not paused.
    modifier whenPoolNotPaused(address pool) {
        _ensureVaultNotPaused();
        _ensurePoolNotPaused(pool);
        _;
    }

    constructor(
        IAuthorizer authorizer,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) Authentication(bytes32(uint256(uint160(address(this))))) {
        if (pauseWindowDuration > MAX_PAUSE_WINDOW_DURATION) {
            revert VaultPauseWindowDurationTooLarge();
        }
        if (bufferPeriodDuration > MAX_BUFFER_PERIOD_DURATION) {
            revert PauseBufferPeriodDurationTooLarge();
        }

        uint256 pauseWindowEndTime = block.timestamp + pauseWindowDuration;

        _vaultPauseWindowEndTime = pauseWindowEndTime;
        _vaultBufferPeriodDuration = bufferPeriodDuration;
        _vaultBufferPeriodEndTime = pauseWindowEndTime + bufferPeriodDuration;

        _authorizer = authorizer;
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

    /// @inheritdoc IVault
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

    /// @inheritdoc IVault
    function settle(IERC20 token) public nonReentrant withHandler returns (uint256 paid) {
        uint256 reservesBefore = _tokenReserves[token];
        _tokenReserves[token] = token.balanceOf(address(this));
        paid = _tokenReserves[token] - reservesBefore;
        // subtraction must be safe
        _supplyCredit(token, paid, msg.sender);
    }

    /// @inheritdoc IVault
    function wire(IERC20 token, address to, uint256 amount) public nonReentrant withHandler {
        // effects
        _takeDebt(token, amount, msg.sender);
        _tokenReserves[token] -= amount;
        // interactions
        token.safeTransfer(to, amount);
    }

    /// @inheritdoc IVault
    function retrieve(IERC20 token, address from, uint256 amount) public nonReentrant withHandler onlyTrustedRouter {
        // effects
        _supplyCredit(token, amount, msg.sender);
        _tokenReserves[token] += amount;
        // interactions
        token.safeTransferFrom(from, address(this), amount);
    }

    /// @inheritdoc IVault
    function getHandler(uint256 index) public view returns (address) {
        if (index >= _handlers.length) {
            revert HandlerOutOfBounds(index);
        }
        return _handlers[index];
    }

    /// @inheritdoc IVault
    function getHandlersCount() external view returns (uint256) {
        return _handlers.length;
    }

    /// @inheritdoc IVault
    function getNonzeroDeltaCount() external view returns (uint256) {
        return _nonzeroDeltaCount;
    }

    /// @inheritdoc IVault
    function getTokenDelta(address user, IERC20 token) external view returns (int256) {
        return _tokenDeltas[user][token];
    }

    /// @inheritdoc IVault
    function getTokenReserve(IERC20 token) external view returns (uint256) {
        return _tokenReserves[token];
    }

    /// @inheritdoc IVault
    function getMinimumPoolTokens() external pure returns (uint256) {
        return _MIN_TOKENS;
    }

    /// @inheritdoc IVault
    function getMaximumPoolTokens() external pure returns (uint256) {
        return _MAX_TOKENS;
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
     *                Positive indicates a debit or a decrease in Vault's assets,
     *                negative indicates a credit or an increase in Vault's assets.
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
                                    Queries
    *******************************************************************************/

    /// @dev Ensure that only static calls are made to the functions with this modifier.
    modifier query() {
        if (!EVMCallModeHelpers.isStaticCall()) {
            revert EVMCallModeHelpers.NotStaticCall();
        }

        if (_isQueryDisabled) {
            revert QueriesDisabled();
        }

        // Add the current handler to the list so `withHandler` does not revert
        _handlers.push(msg.sender);
        _;
    }

    /// @inheritdoc IVault
    function quote(bytes calldata data) external payable query returns (bytes memory result) {
        // Forward the incoming call to the original sender of this transaction.
        return (msg.sender).functionCallWithValue(data, msg.value);
    }

    /// @inheritdoc IVault
    function disableQuery() external authenticate {
        _isQueryDisabled = true;
    }

    /// @inheritdoc IVault
    function isQueryDisabled() external view returns (bool) {
        return _isQueryDisabled;
    }

    /*******************************************************************************
                                    Pool Tokens
    *******************************************************************************/

    /// @inheritdoc IVault
    function totalSupply(address token) external view returns (uint256) {
        return _totalSupply(token);
    }

    /// @inheritdoc IVault
    function balanceOf(address token, address account) external view returns (uint256) {
        return _balanceOf(token, account);
    }

    /// @inheritdoc IVault
    function allowance(address token, address owner, address spender) external view returns (uint256) {
        return _allowance(token, owner, spender);
    }

    /// @inheritdoc IVault
    function transfer(address owner, address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, owner, to, amount);
        return true;
    }

    /// @inheritdoc IVault
    function approve(address owner, address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, owner, spender, amount);
        return true;
    }

    /// @inheritdoc IVault
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

    // Needed to avoid "stack too deep"
    struct SharedLocals {
        PoolConfig config;
        IERC20[] tokens;
        uint256[] balancesRaw;
        uint256[] scalingFactors;
        uint256[] balancesScaled18;
        uint256 tokenIndex;
    }

    // For add/remove liquidity
    function _populateSharedLiquidityLocals(
        address pool,
        bool addingLiquidity
    ) private view returns (SharedLocals memory vars) {
        (vars.tokens, vars.balancesRaw, vars.scalingFactors) = _getPoolTokenInfo(pool);
        vars.config = _poolConfig[pool].toPoolConfig();

        uint256 numTokens = vars.tokens.length;
        vars.balancesScaled18 = new uint256[](numTokens);

        // Round up when adding liquidity:
        // If proportional, higher balances = higher proportional amountsIn, favoring the pool.
        // If unbalanced, higher balances = lower invariant ratio with fees.
        // bptOut = supply * (ratio - 1), so lower ratio = less bptOut, favoring the pool.
        //
        // Round down when removing liquidity:
        // If proportional, lower balances = lower proportional amountsOut, favoring the pool.
        // If unbalanced, lower balances = lower invariant ratio without fees.
        // bptIn = supply * (1 - ratio), so lower ratio = more bptIn, favoring the pool.
        //
        // See `calcBptOutGivenExactTokensIn` and `calcBptInGivenExactTokensOut` WeightedMath tests.

        for (uint256 i = 0; i < numTokens; i++) {
            vars.balancesScaled18[i] = addingLiquidity
                ? vars.balancesRaw[i].toScaled18RoundUp(vars.scalingFactors[i])
                : vars.balancesRaw[i].toScaled18RoundDown(vars.scalingFactors[i]);
        }
    }

    // Needed to avoid "stack too deep"
    struct SwapLocals {
        // Inline the shared struct fields vs. nesting, trading off verbosity for gas/memory/bytecode savings.
        PoolConfig config;
        uint256[] balancesRaw;
        uint256[] scalingFactors;
        uint256[] balancesScaled18;
        uint256 numTokens;
        uint256 indexIn;
        uint256 indexOut;
        uint256 tokenInBalance;
        uint256 tokenOutBalance;
        uint256 amountGivenScaled18;
        uint256 amountCalculatedScaled18;
        uint256 swapFeeAmount;
        uint256 swapFeePercentage;
        uint256 protocolSwapFeeAmount;
    }

    function _populateSwapLocals(
        SwapParams memory params
    ) private view returns (SwapLocals memory vars, EnumerableMap.IERC20ToUint256Map storage poolBalances) {
        poolBalances = _poolTokenBalances[params.pool];
        vars.numTokens = poolBalances.length();
        vars.config = _poolConfig[params.pool].toPoolConfig();
        vars.scalingFactors = PoolConfigLib.getScalingFactors(vars.config, vars.numTokens);
        vars.balancesRaw = new uint256[](vars.numTokens);
        vars.balancesScaled18 = new uint256[](vars.numTokens);
        for (uint256 i = 0; i < vars.numTokens; i++) {
            vars.balancesRaw[i] = poolBalances.unchecked_valueAt(i);
            // Rounding down is legacy behavior, and seems the right direction generally, as described below.
            // However, likely because of the non-linearity introduced by power functions, the calculation
            // error for very small values is greater than the rounding correction, so it is possible that
            // rounding down here will not decrease `amountOut` or increase `amountIn`. Further measures
            // are required to ensure safety.
            //
            // In the GivenIn case, lower balances cause `calcOutGivenIn` to calculate a lower amountOut.
            // In the GivenOut case, lower balances cause `calcInGivenOut` to calculate a higher amountIn.
            // See `calcOutGivenIn` and `calcInGivenOut` WeightedMath tests.
            vars.balancesScaled18[i] = poolBalances.unchecked_valueAt(i).toScaled18RoundDown(vars.scalingFactors[i]);
        }

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

        for (uint256 i = 0; i < vars.numTokens; i++) {
            // We know from the above checks that `i` is a valid token index and can use `unchecked_valueAt`
            // to save storage reads.
            uint256 balance = poolBalances.unchecked_valueAt(i);

            if (i == vars.indexIn) {
                vars.tokenInBalance = balance;
            } else if (i == vars.indexOut) {
                vars.tokenOutBalance = balance;
            }
        }
    }

    /*******************************************************************************
                                          Swaps
    *******************************************************************************/

    /// @inheritdoc IVault
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

        (SwapLocals memory vars, EnumerableMap.IERC20ToUint256Map storage poolBalances) = _populateSwapLocals(params);

        // If the amountGiven is entering the pool math (GivenIn), round down, since a lower apparent amountIn leads
        // to a lower calculated amountOut, favoring the pool.
        vars.amountGivenScaled18 = params.kind == SwapKind.GIVEN_IN
            ? params.amountGivenRaw.toScaled18RoundDown(vars.scalingFactors[vars.indexIn])
            : params.amountGivenRaw.toScaled18RoundUp(vars.scalingFactors[vars.indexOut]);

        vars.swapFeePercentage = _getSwapFeePercentage(vars.config);

        if (vars.swapFeePercentage > 0 && params.kind == IVault.SwapKind.GIVEN_OUT) {
            // Round up to avoid losses during precision loss.
            vars.swapFeeAmount =
                vars.amountGivenScaled18.divUp(vars.swapFeePercentage.complement()) -
                vars.amountGivenScaled18;
        }

        // Add swap fee to the amountGiven to account for the fee taken in GIVEN_OUT swap on tokenOut
        // Perform the swap request callback and compute the new balances for 'token in' and 'token out' after the swap
        vars.amountCalculatedScaled18 = IBasePool(params.pool).onSwap(
            IBasePool.SwapParams({
                kind: params.kind,
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                amountGivenScaled18: vars.amountGivenScaled18 + vars.swapFeeAmount,
                balancesScaled18: vars.balancesScaled18,
                indexIn: vars.indexIn,
                indexOut: vars.indexOut,
                sender: msg.sender,
                userData: params.userData
            })
        );

        if (vars.swapFeePercentage > 0 && params.kind == IVault.SwapKind.GIVEN_IN) {
            // Swap fee is a percentage of the amountCalculated for the GIVEN_IN swap
            // Round up to avoid losses during precision loss.
            vars.swapFeeAmount = vars.amountCalculatedScaled18.mulUp(vars.swapFeePercentage);
            // Should substract the fee from the amountCalculated for GIVEN_IN swap
            vars.amountCalculatedScaled18 -= vars.swapFeeAmount;
        }

        // For `GivenIn` the amount calculated is leaving the Vault, so we round down.
        // Round up when entering the Vault on `GivenOut`.
        amountCalculated = params.kind == SwapKind.GIVEN_IN
            ? vars.amountCalculatedScaled18.toRawRoundDown(vars.scalingFactors[vars.indexOut])
            : vars.amountCalculatedScaled18.toRawRoundUp(vars.scalingFactors[vars.indexIn]);

        (amountIn, amountOut) = params.kind == SwapKind.GIVEN_IN
            ? (params.amountGivenRaw, amountCalculated)
            : (amountCalculated, params.amountGivenRaw);

        // Charge protocolSwapFee
        if (vars.swapFeeAmount > 0 && _protocolSwapFeePercentage > 0) {
            // Always charge fees on tokenOut. Store amount in native decimals.
            vars.protocolSwapFeeAmount = vars.swapFeeAmount.mulUp(_protocolSwapFeePercentage).toRawRoundDown(
                vars.scalingFactors[vars.indexOut]
            );

            _protocolSwapFees[params.tokenOut] += vars.protocolSwapFeeAmount;
        }

        // Use `unchecked_setAt` to save storage reads.
        poolBalances.unchecked_setAt(vars.indexIn, vars.tokenInBalance + amountIn);
        poolBalances.unchecked_setAt(vars.indexOut, vars.tokenOutBalance - amountOut - vars.protocolSwapFeeAmount);

        // Account amountIn of tokenIn
        _takeDebt(params.tokenIn, amountIn, msg.sender);
        // Account amountOut of tokenOut
        _supplyCredit(params.tokenOut, amountOut, msg.sender);

        if (vars.config.callbacks.shouldCallAfterSwap) {
            (uint256 amountInScaled18, uint256 amountOutScaled18) = params.kind == SwapKind.GIVEN_IN
                ? (vars.amountGivenScaled18, vars.amountCalculatedScaled18)
                : (vars.amountCalculatedScaled18, vars.amountGivenScaled18);

            // if callback is enabled, then update balances
            if (
                IBasePool(params.pool).onAfterSwap(
                    IBasePool.AfterSwapParams({
                        kind: params.kind,
                        tokenIn: params.tokenIn,
                        tokenOut: params.tokenOut,
                        amountInScaled18: amountInScaled18,
                        amountOutScaled18: amountOutScaled18,
                        tokenInBalanceScaled18: vars.balancesScaled18[vars.indexIn] + amountInScaled18,
                        tokenOutBalanceScaled18: vars.balancesScaled18[vars.indexOut] - amountOutScaled18,
                        sender: msg.sender,
                        userData: params.userData
                    }),
                    vars.amountCalculatedScaled18
                ) == false
            ) {
                revert CallbackFailed();
            }
        }

        emit Swap(params.pool, params.tokenIn, params.tokenOut, amountIn, amountOut, vars.swapFeeAmount);
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

    /// @inheritdoc IVault
    function registerPool(
        address pool,
        IERC20[] memory tokens,
        uint256 pauseWindowEndTime,
        address pauseManager,
        PoolCallbacks calldata poolCallbacks,
        LiquidityManagement calldata liquidityManagement
    ) external nonReentrant whenVaultNotPaused {
        _registerPool(pool, tokens, pauseWindowEndTime, pauseManager, poolCallbacks, liquidityManagement);
    }

    /// @inheritdoc IVault
    function isPoolRegistered(address pool) external view returns (bool) {
        return _isPoolRegistered(pool);
    }

    /// @inheritdoc IVault
    function isPoolInitialized(address pool) external view returns (bool) {
        return _isPoolInitialized(pool);
    }

    /// @inheritdoc IVault
    function isPoolInRecoveryMode(address pool) external view returns (bool) {
        return _isPoolInRecoveryMode(pool);
    }

    /// @inheritdoc IVault
    function getPoolConfig(address pool) external view returns (PoolConfig memory) {
        return _poolConfig[pool].toPoolConfig();
    }

    /// @inheritdoc IVault
    function getPoolTokens(address pool) external view withRegisteredPool(pool) returns (IERC20[] memory) {
        return _getPoolTokens(pool);
    }

    /// @inheritdoc IVault
    function getPoolTokenInfo(
        address pool
    )
        external
        view
        withRegisteredPool(pool)
        returns (IERC20[] memory tokens, uint256[] memory balancesRaw, uint256[] memory scalingFactors)
    {
        return _getPoolTokenInfo(pool);
    }

    /// @dev Reverts unless `pool` corresponds to a registered Pool.
    modifier withRegisteredPool(address pool) {
        _ensureRegisteredPool(pool);
        _;
    }

    /// @dev Reverts unless `pool` corresponds to a registered Pool.
    function _ensureRegisteredPool(address pool) internal view {
        if (!_isPoolRegistered(pool)) {
            revert PoolNotRegistered(pool);
        }
    }

    /**
     * @dev The function will register the pool, setting its tokens with an initial balance of zero.
     * The function also checks for valid token addresses and ensures that the pool and tokens aren't
     * already registered.
     *
     * Emits a `PoolRegistered` event upon successful registration.
     */
    function _registerPool(
        address pool,
        IERC20[] memory tokens,
        uint256 pauseWindowEndTime,
        address pauseManager,
        PoolCallbacks memory callbackConfig,
        LiquidityManagement memory liquidityManagement
    ) internal {
        // Ensure the pool isn't already registered
        if (_isPoolRegistered(pool)) {
            revert PoolAlreadyRegistered(pool);
        }

        uint256 numTokens = tokens.length;

        if (numTokens < _MIN_TOKENS) {
            revert MinTokens();
        }
        if (numTokens > _MAX_TOKENS) {
            revert MaxTokens();
        }

        // Retrieve or create the pool's token balances mapping
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];

        uint8[] memory tokenDecimalDiffs = new uint8[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token = tokens[i];

            // Ensure that the token address is valid
            if (token == IERC20(address(0))) {
                revert InvalidToken();
            }

            // Register the token with an initial balance of zero.
            // Note: EnumerableMaps require an explicit initial value when creating a key-value pair.
            bool added = poolTokenBalances.set(token, 0);

            // Ensure the token isn't already registered for the pool
            if (!added) {
                revert TokenAlreadyRegistered(token);
            }

            tokenDecimalDiffs[i] = uint8(18) - IERC20Metadata(address(token)).decimals();
        }

        // Store the pause manager. A zero address means default to the authorizer.
        _poolPauseManagers[pool] = pauseManager;

        // Store config and mark the pool as registered
        PoolConfig memory config = PoolConfigLib.toPoolConfig(_poolConfig[pool]);

        config.isPoolRegistered = true;
        config.callbacks = callbackConfig;
        config.liquidityManagement = liquidityManagement;
        config.tokenDecimalDiffs = PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs);
        config.pauseWindowEndTime = pauseWindowEndTime.toUint32();
        _poolConfig[pool] = config.fromPoolConfig();

        // Emit an event to log the pool registration (pass msg.sender as the factory argument)
        emit PoolRegistered(
            pool,
            msg.sender,
            tokens,
            pauseWindowEndTime,
            pauseManager,
            callbackConfig,
            liquidityManagement
        );
    }

    /// @dev See `isPoolRegistered`
    function _isPoolRegistered(address pool) internal view returns (bool) {
        return _poolConfig[pool].isPoolRegistered();
    }

    /// @dev See `isPoolInRecoveryMode`
    function _isPoolInRecoveryMode(address pool) internal view returns (bool) {
        return _poolConfig[pool].isPoolInRecoveryMode();
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
     * @notice Fetches the scaled up balances for a given pool.
     * @dev Utilizes an enumerable map to obtain pool token balances.
     * The function is structured to minimize storage reads by leveraging the `unchecked_at` method.
     *
     * @param pool The address of the pool
     * @return balancesScaled18 An array of token balances, scaled up and rounded as directed
     */
    function _getPoolBalancesScaled18(
        address pool,
        bool roundUp
    ) internal view returns (uint256[] memory balancesScaled18) {
        // Retrieve the mapping of tokens and their balances for the specified pool.
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];
        uint256 numTokens = poolTokenBalances.length();

        uint256[] memory scalingFactors = PoolConfigLib.getScalingFactors(_poolConfig[pool].toPoolConfig(), numTokens);

        // Initialize array to store balances based on the number of tokens in the pool.
        // Will be read raw, then upscaled and rounded as directed.
        balancesScaled18 = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length,
            // we can safely use `unchecked_at`. This ensures that `i` is a valid token index and minimizes
            // storage reads.
            (, balancesScaled18[i]) = poolTokenBalances.unchecked_at(i);
        }

        roundUp
            ? balancesScaled18.toScaled18RoundUpArray(scalingFactors)
            : balancesScaled18.toScaled18RoundDownArray(scalingFactors);
    }

    function _getPoolTokenInfo(
        address pool
    ) internal view returns (IERC20[] memory tokens, uint256[] memory balancesRaw, uint256[] memory scalingFactors) {
        // Retrieve the mapping of tokens and their balances for the specified pool.
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];
        uint256 numTokens = poolTokenBalances.length();

        scalingFactors = PoolConfigLib.getScalingFactors(_poolConfig[pool].toPoolConfig(), numTokens);

        // Initialize arrays to store tokens and balances based on the number of tokens in the pool.
        // Will be read raw, then upscaled and rounded as directed.
        tokens = new IERC20[](numTokens);
        balancesRaw = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length,
            // we can safely use `unchecked_at`. This ensures that `i` is a valid token index and minimizes
            // storage reads.
            (tokens[i], balancesRaw[i]) = poolTokenBalances.unchecked_at(i);
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

    /// @inheritdoc IVault
    function initialize(
        address pool,
        address to,
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        bytes memory userData
    )
        external
        withHandler
        nonReentrant
        withRegisteredPool(pool)
        whenPoolNotPaused(pool)
        returns (uint256 bptAmountOut)
    {
        PoolConfig memory config = _poolConfig[pool].toPoolConfig();

        if (config.isPoolInitialized) {
            revert PoolAlreadyInitialized(pool);
        }

        InputHelpers.ensureInputLengthMatch(tokens.length, exactAmountsIn.length);

        _validateTokensAndGetBalances(pool, tokens);

        for (uint256 i = 0; i < tokens.length; ++i) {
            // Debit of token[i] for amountIn
            _takeDebt(tokens[i], exactAmountsIn[i], msg.sender);
        }

        // Store the new Pool balances.
        _setPoolBalances(pool, exactAmountsIn);
        emit PoolBalanceChanged(pool, to, tokens, exactAmountsIn.unsafeCastToInt256(true));

        // Store config and mark the pool as initialized
        config.isPoolInitialized = true;
        _poolConfig[pool] = config.fromPoolConfig();

        // Finally, call pool hook. Doing this at the end also means we do not need to downscale exact amounts in.
        // Amounts are entering pool math, so round down. A lower invariant after the join means less bptOut,
        // favoring the pool.
        exactAmountsIn.toScaled18RoundDownArray(PoolConfigLib.getScalingFactors(config, tokens.length));

        bptAmountOut = IBasePool(pool).onInitialize(exactAmountsIn, userData);

        if (bptAmountOut < _MINIMUM_BPT) {
            revert BptAmountBelowAbsoluteMin();
        }

        // When adding liquidity, we must mint tokens concurrently with updating pool balances,
        // as the pool's math relies on totalSupply.
        // At this point we know that bptAmountOut >= _MINIMUM_BPT, so this will not revert.
        bptAmountOut -= _MINIMUM_BPT;
        _mint(address(pool), to, bptAmountOut);
        _mintToAddressZero(address(pool), _MINIMUM_BPT);

        // Emit an event to log the pool initialization
        emit PoolInitialized(pool);
    }

    /// @inheritdoc IVault
    function addLiquidity(
        AddLiquidityParams memory params
    )
        external
        withHandler
        withInitializedPool(params.pool)
        whenPoolNotPaused(params.pool)
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData)
    {
        // Set `addingLiquidity` parameter to true to set rounding direction for balances.
        SharedLocals memory vars = _populateSharedLiquidityLocals(params.pool, true);
        InputHelpers.ensureInputLengthMatch(vars.tokens.length, params.maxAmountsIn.length);

        // Amounts are entering pool math, so round down.
        params.maxAmountsIn.toScaled18RoundDownArray(vars.scalingFactors);

        if (vars.config.callbacks.shouldCallBeforeAddLiquidity) {
            // TODO: check if `before` needs kind.
            if (
                IBasePool(params.pool).onBeforeAddLiquidity(
                    params.to,
                    params.maxAmountsIn,
                    params.minBptAmountOut,
                    vars.balancesScaled18,
                    params.userData
                ) == false
            ) {
                revert CallbackFailed();
            }

            // The callback might alter the balances, so we need to read them again to ensure that the data is
            // fresh moving forward.
            // We also need to upscale (adding liquidity, so round up) again.
            vars.balancesScaled18 = _getPoolBalancesScaled18(params.pool, true);
        }

        // The bulk of the work is done here: the corresponding Pool callback is invoked
        // its final balances are computed
        // This function is non-reentrant, as it performs the accounting updates.
        uint256[] memory amountsInScaled18;
        (amountsIn, amountsInScaled18, bptAmountOut, returnData) = _addLiquidity(vars, params);

        if (vars.config.callbacks.shouldCallAfterAddLiquidity) {
            if (
                IBasePool(params.pool).onAfterAddLiquidity(
                    params.to,
                    amountsInScaled18,
                    bptAmountOut,
                    vars.balancesScaled18,
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
        SharedLocals memory vars,
        AddLiquidityParams memory params
    )
        internal
        nonReentrant
        returns (
            uint256[] memory amountsIn,
            uint256[] memory amountsInScaled18,
            uint256 bptAmountOut,
            bytes memory returnData
        )
    {
        if (params.kind == AddLiquidityKind.PROPORTIONAL) {
            _poolConfig[params.pool].requireSupportsAddLiquidityProportional();

            bptAmountOut = params.minBptAmountOut;
            amountsInScaled18 = BasePoolMath.computeProportionalAmountsIn(
                vars.balancesScaled18,
                _totalSupply(params.pool),
                bptAmountOut
            );
        } else if (params.kind == AddLiquidityKind.UNBALANCED) {
            amountsInScaled18 = params.maxAmountsIn;
            bptAmountOut = BasePoolMath.computeAddLiquidityUnbalanced(
                vars.balancesScaled18,
                params.maxAmountsIn,
                _totalSupply(params.pool),
                _getSwapFeePercentage(vars.config),
                IBasePool(params.pool).getInvariant
            );
        } else if (params.kind == AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            _poolConfig[params.pool].requireSupportsAddLiquiditySingleTokenExactOut();

            vars.tokenIndex = InputHelpers.getSingleInputIndex(params.maxAmountsIn);
            bptAmountOut = params.minBptAmountOut;

            amountsInScaled18 = params.maxAmountsIn;
            amountsInScaled18[vars.tokenIndex] = IBasePool(params.pool).onAddLiquiditySingleTokenExactOut(
                params.to,
                vars.tokenIndex,
                bptAmountOut,
                vars.balancesScaled18
            );
        } else if (params.kind == AddLiquidityKind.CUSTOM) {
            _poolConfig[params.pool].requireSupportsAddLiquidityCustom();

            (amountsInScaled18, bptAmountOut, returnData) = IBasePool(params.pool).onAddLiquidityCustom(
                params.to,
                params.maxAmountsIn,
                params.minBptAmountOut,
                vars.balancesScaled18,
                params.userData
            );
        } else {
            revert InvalidAddLiquidityKind();
        }

        // TODO: enforce min and max.
        uint256 numTokens = vars.tokens.length;
        amountsIn = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            // amountsIn are amounts entering the Pool, so we round up.
            // Do not mutate in place yet, as we need them scaled for the `onAfterAddLiquidity` callback
            uint256 amountIn = amountsInScaled18[i].toRawRoundUp(vars.scalingFactors[i]);

            // Debit of token[i] for amountIn
            _takeDebt(vars.tokens[i], amountIn, msg.sender);

            // We need regular balances to complete the accounting, and the upscaled balances
            // to use in the `after` callback later on.
            vars.balancesRaw[i] += amountIn;
            vars.balancesScaled18[i] += amountsInScaled18[i];

            amountsIn[i] = amountIn;
        }

        // Store the new pool balances.
        _setPoolBalances(params.pool, vars.balancesRaw);

        // When adding liquidity, we must mint tokens concurrently with updating pool balances,
        // as the pool's math relies on totalSupply.
        _mint(address(params.pool), params.to, bptAmountOut);

        emit PoolBalanceChanged(params.pool, params.to, vars.tokens, amountsIn.unsafeCastToInt256(true));
    }

    /// @inheritdoc IVault
    function removeLiquidity(RemoveLiquidityParams memory params)
        external
        withInitializedPool(params.pool)
        whenPoolNotPaused(params.pool)
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData)
    {
        // Set `addingLiquidity` parameter to false to set rounding direction for balances.
        SharedLocals memory vars = _populateSharedLiquidityLocals(params.pool, false);
        InputHelpers.ensureInputLengthMatch(vars.tokens.length, params.minAmountsOut.length);

        // Amounts are entering pool math; higher amounts would burn more BPT, so round up to favor the pool.
        params.minAmountsOut.toScaled18RoundUpArray(vars.scalingFactors);

        if (vars.config.callbacks.shouldCallBeforeRemoveLiquidity) {
            // TODO: check if `before` callback needs kind.
            if (
                IBasePool(params.pool).onBeforeRemoveLiquidity(
                    params.from,
                    params.maxBptAmountIn,
                    params.minAmountsOut,
                    vars.balancesScaled18,
                    params.userData
                ) == false
            ) {
                revert CallbackFailed();
            }
            // The callback might alter the balances, so we need to read them again to ensure that the data is
            // fresh moving forward.
            // We also need to upscale (removing liquidity, so round down) again.
            vars.balancesScaled18 = _getPoolBalancesScaled18(params.pool, false);
        }

        // The bulk of the work is done here: the corresponding Pool callback is invoked,
        // and its final balances are computed
        // This function is non-reentrant, as it performs the accounting updates.
        uint256[] memory upscaledAmountsOut;
        (bptAmountIn, amountsOut, upscaledAmountsOut, returnData) = _removeLiquidity(
            vars,
            params
        );

        if (vars.config.callbacks.shouldCallAfterRemoveLiquidity) {
            if (
                IBasePool(params.pool).onAfterRemoveLiquidity(
                    params.from,
                    bptAmountIn,
                    upscaledAmountsOut,
                    vars.balancesScaled18,
                    params.userData
                ) == false
            ) {
                revert CallbackFailed();
            }
        }
    }

    /// @inheritdoc IVault
    function removeLiquidityRecovery(
        address pool,
        address from,
        uint256 exactBptAmountIn
    ) external nonReentrant withInitializedPool(pool) onlyInRecoveryMode(pool) returns (uint256[] memory amountsOut) {
        SharedLocals memory vars = _populateSharedLiquidityLocals(pool, false);

        uint256[] memory upscaledAmountsOut = BasePoolMath.computeProportionalAmountsOut(
            vars.balancesScaled18,
            _totalSupply(pool),
            exactBptAmountIn
        );

        amountsOut = _removeLiquidityUpdateAccounting(vars, pool, from, exactBptAmountIn, upscaledAmountsOut);
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
        SharedLocals memory vars,
        RemoveLiquidityParams memory params
    )
        internal
        nonReentrant
        returns (
            uint256 bptAmountIn,
            uint256[] memory amountsOut,
            uint256[] memory upscaledAmountsOut,
            bytes memory returnData
        )
    {
        if (params.kind == RemoveLiquidityKind.PROPORTIONAL) {
            bptAmountIn = params.maxBptAmountIn;
            upscaledAmountsOut = BasePoolMath.computeProportionalAmountsOut(
                vars.balancesScaled18,
                _totalSupply(params.pool),
                bptAmountIn
            );
        } else if (params.kind == RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN) {
            vars.tokenIndex = InputHelpers.getSingleInputIndex(params.minAmountsOut);
            bptAmountIn = params.maxBptAmountIn;

            upscaledAmountsOut = params.minAmountsOut;
            upscaledAmountsOut[vars.tokenIndex] = IBasePool(params.pool).onRemoveLiquiditySingleTokenExactIn(
                params.from,
                vars.tokenIndex,
                bptAmountIn,
                vars.balancesScaled18
            );
        } else if (params.kind == RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            vars.tokenIndex = InputHelpers.getSingleInputIndex(params.minAmountsOut);
            upscaledAmountsOut = params.minAmountsOut;

            bptAmountIn = BasePoolMath.computeRemoveLiquiditySingleTokenExactOut(
                vars.balancesScaled18,
                vars.tokenIndex,
                upscaledAmountsOut[vars.tokenIndex],
                _totalSupply(params.pool),
                _getSwapFeePercentage(vars.config),
                IBasePool(params.pool).getInvariant
            );
        } else if (params.kind == RemoveLiquidityKind.CUSTOM) {
            (bptAmountIn, upscaledAmountsOut, returnData) = IBasePool(params.pool).onRemoveLiquidityCustom(
                params.from,
                params.maxBptAmountIn,
                params.minAmountsOut,
                vars.balancesScaled18,
                params.userData
            );
        } else {
            revert InvalidRemoveLiquidityKind();
        }

        // TODO: enforce min and max. Maybe inside `_removeLiquidityUpdateAccounting`, where we iterate the tokens?
        amountsOut = _removeLiquidityUpdateAccounting(vars, params.pool, params.from, bptAmountIn, upscaledAmountsOut);
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
        SharedLocals memory vars,
        address pool,
        address from,
        uint256 bptAmountIn,
        uint256[] memory amountsOutScaled18
    ) internal returns (uint256[] memory amountsOut) {
        uint256 numTokens = vars.tokens.length;
        amountsOut = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            // amountsOut are amounts exiting the Pool, so we round down.
            // Need amountsOut scaled for the `onAfterRemoveLiquidity` callback,
            // so convert each amount individually here to raw decimals to compute unscaled `finalBalances`.
            uint256 amountOut = amountsOutScaled18[i].toRawRoundDown(vars.scalingFactors[i]);

            // Credit token[i] for amountIn
            _supplyCredit(vars.tokens[i], amountOut, msg.sender);

            // Compute the new Pool balances. A Pool's token balance always decreases after an exit (potentially by 0).
            // We need regular balances to complete the accounting, and the upscaled balances
            // to use in the `after` callback later on.
            vars.balancesRaw[i] -= amountOut;
            vars.balancesScaled18[i] -= amountsOutScaled18[i];
            amountsOut[i] = amountOut;
        }

        // Store the new pool balances.
        _setPoolBalances(pool, vars.balancesRaw);

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
        _burn(address(pool), from, bptAmountIn);

        emit PoolBalanceChanged(
            pool,
            from,
            vars.tokens,
            // We can unsafely cast to int256 because balances are actually stored as uint112
            amountsOut.unsafeCastToInt256(false)
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

    /**
     * @dev Returns the total balances for `pool`'s `expectedTokens`.
     * `expectedTokens` must exactly equal the token array returned by `getPoolTokens`: both arrays must have the same
     * length, elements and order. This is only called after pool registration, which has guarantees the number of
     * tokens is valid (i.e., between the minimum and maximum token count).
     */
    function _validateTokensAndGetBalances(
        address pool,
        IERC20[] memory expectedTokens
    ) private view returns (uint256[] memory) {
        (IERC20[] memory actualTokens, uint256[] memory balancesRaw, ) = _getPoolTokenInfo(pool);
        InputHelpers.ensureInputLengthMatch(actualTokens.length, expectedTokens.length);

        for (uint256 i = 0; i < actualTokens.length; ++i) {
            if (actualTokens[i] != expectedTokens[i]) {
                revert TokensMismatch(pool, address(expectedTokens[i]), address(actualTokens[i]));
            }
        }

        return balancesRaw;
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
                                    Recovery Mode
    *******************************************************************************/

    /**
     * @dev Place on functions that may only be called when the associated pool is in recovery mode.
     * @param pool The pool
     */
    modifier onlyInRecoveryMode(address pool) {
        _ensurePoolInRecoveryMode(pool);
        _;
    }

    /// @inheritdoc IVault
    function enableRecoveryMode(address pool) external withRegisteredPool(pool) authenticate {
        _ensurePoolNotInRecoveryMode(pool);
        _setPoolRecoveryMode(pool, true);
    }

    /// @inheritdoc IVault
    function disableRecoveryMode(address pool) external withRegisteredPool(pool) authenticate {
        _ensurePoolInRecoveryMode(pool);
        _setPoolRecoveryMode(pool, false);
    }

    function _setPoolRecoveryMode(address pool, bool recoveryMode) internal {
        // Update poolConfig
        PoolConfig memory config = PoolConfigLib.toPoolConfig(_poolConfig[pool]);
        config.isPoolInRecoveryMode = recoveryMode;
        _poolConfig[pool] = config.fromPoolConfig();

        emit PoolRecoveryModeStateChanged(pool, recoveryMode);
    }

    /**
     * @dev Reverts if the pool is in recovery mode.
     * @param pool The pool
     */
    function _ensurePoolNotInRecoveryMode(address pool) internal view {
        if (_isPoolInRecoveryMode(pool)) {
            revert PoolInRecoveryMode(pool);
        }
    }

    /**
     * @dev Reverts if the pool is not in recovery mode.
     * @param pool The pool
     */
    function _ensurePoolInRecoveryMode(address pool) internal view {
        if (!_isPoolInRecoveryMode(pool)) {
            revert PoolNotInRecoveryMode(pool);
        }
    }

    /*******************************************************************************
                                        Fees
    *******************************************************************************/

    /// @inheritdoc IVault
    function setProtocolSwapFeePercentage(uint256 newProtocolSwapFeePercentage) external authenticate {
        if (newProtocolSwapFeePercentage > _MAX_PROTOCOL_SWAP_FEE_PERCENTAGE) {
            revert ProtocolSwapFeePercentageTooHigh();
        }
        _protocolSwapFeePercentage = newProtocolSwapFeePercentage;
        emit ProtocolSwapFeePercentageChanged(newProtocolSwapFeePercentage);
    }

    /// @inheritdoc IVault
    function getProtocolSwapFeePercentage() external view returns (uint256) {
        return _protocolSwapFeePercentage;
    }

    /// @inheritdoc IVault
    function getProtocolSwapFee(address token) external view returns (uint256) {
        return _protocolSwapFees[IERC20(token)];
    }

    /// @inheritdoc IVault
    function collectProtocolFees(IERC20[] calldata tokens) external authenticate nonReentrant {
        for (uint256 index = 0; index < tokens.length; index++) {
            IERC20 token = tokens[index];
            uint256 amount = _protocolSwapFees[token];
            // checks
            if (amount > 0) {
                // effects
                // set fees to zero for the token
                _protocolSwapFees[token] = 0;
                // interactions
                token.safeTransfer(msg.sender, amount);
                // emit an event
                emit ProtocolFeeCollected(token, amount);
            }
        }
    }

    /**
     * @inheritdoc IVault
     * @dev This is a permissioned function, disabled if the pool is paused. The swap fee must be <=
     * MAX_SWAP_FEE_PERCENTAGE. Emits the SwapFeePercentageChanged event.
     */
    function setStaticSwapFeePercentage(
        address pool,
        uint256 swapFeePercentage
    ) external authenticate withRegisteredPool(pool) whenPoolNotPaused(pool) {
        _setStaticSwapFeePercentage(pool, swapFeePercentage);
    }

    function _setStaticSwapFeePercentage(address pool, uint256 swapFeePercentage) internal virtual {
        if (swapFeePercentage > _MAX_SWAP_FEE_PERCENTAGE) {
            revert SwapFeePercentageTooHigh();
        }

        PoolConfig memory config = PoolConfigLib.toPoolConfig(_poolConfig[pool]);
        config.staticSwapFeePercentage = swapFeePercentage.toUint64();
        _poolConfig[pool] = config.fromPoolConfig();

        emit SwapFeePercentageChanged(pool, swapFeePercentage);
    }

    /// @inheritdoc IVault
    function getStaticSwapFeePercentage(address pool) external view returns (uint256) {
        return PoolConfigLib.toPoolConfig(_poolConfig[pool]).staticSwapFeePercentage;
    }

    /*******************************************************************************
                                    Authentication
    *******************************************************************************/

    /// @inheritdoc IVault
    function getAuthorizer() external view returns (IAuthorizer) {
        return _authorizer;
    }

    /// @inheritdoc IVault
    function setAuthorizer(IAuthorizer newAuthorizer) external nonReentrant authenticate {
        _authorizer = newAuthorizer;

        emit AuthorizerChanged(newAuthorizer);
    }

    /// @dev Access control is delegated to the Authorizer
    function _canPerform(bytes32 actionId, address user) internal view override returns (bool) {
        return _authorizer.canPerform(actionId, user, address(this));
    }

    /*******************************************************************************
                                    Vault Pausing
    *******************************************************************************/

    /// @inheritdoc IVault
    function isVaultPaused() external view returns (bool) {
        return _isVaultPaused();
    }

    /// @inheritdoc IVault
    function getVaultPausedState() public view returns (bool, uint256, uint256) {
        return (_isVaultPaused(), _vaultPauseWindowEndTime, _vaultBufferPeriodEndTime);
    }

    /// @inheritdoc IVault
    function pauseVault() external authenticate {
        _setVaultPaused(true);
    }

    /// @inheritdoc IVault
    function unpauseVault() external authenticate {
        _setVaultPaused(false);
    }

    /**
     * @dev For gas efficiency, storage is only read before `_vaultBufferPeriodEndTime`. Once we're past that
     * timestamp, the expression short-circuits false, and the Vault is permanently unpaused.
     */
    function _isVaultPaused() internal view returns (bool) {
        return block.timestamp <= _vaultBufferPeriodEndTime && _vaultPaused;
    }

    /**
     * @dev The contract can only be paused until the end of the Pause Window, and
     * unpaused until the end of the Buffer Period.
     */
    function _setVaultPaused(bool pausing) internal {
        if (_isVaultPaused()) {
            if (pausing) {
                // Already paused, and we're trying to pause it again.
                revert VaultPaused();
            }

            // The Vault can always be unpaused while it's paused.
            // When the buffer period expires, `_isVaultPaused` will return false, so we would be in the outside
            // else clause, where trying to unpause will revert unconditionally.
        } else {
            if (pausing) {
                // Not already paused; we can pause within the window.
                if (block.timestamp >= _vaultPauseWindowEndTime) {
                    revert VaultPauseWindowExpired();
                }
            } else {
                // Not paused, and we're trying to unpause it.
                revert VaultNotPaused();
            }
        }

        _vaultPaused = pausing;

        emit VaultPausedStateChanged(pausing);
    }

    /// @dev Reverts if the Vault is paused.
    function _ensureVaultNotPaused() internal view {
        if (_isVaultPaused()) {
            revert VaultPaused();
        }
    }

    /*******************************************************************************
                                     Pool Pausing
    *******************************************************************************/

    modifier onlyAuthenticatedPauser(address pool) {
        address pauseManager = _poolPauseManagers[pool];

        if (pauseManager == address(0)) {
            // If there is no pause manager, default to the authorizer.
            _authenticateCaller();
        } else {
            // Sender must be the pause manager.
            if (msg.sender != pauseManager) {
                revert SenderIsNotPauseManager(pool);
            }
        }
        _;
    }

    /// @inheritdoc IVault
    function isPoolPaused(address pool) external view withRegisteredPool(pool) returns (bool) {
        return _isPoolPaused(pool);
    }

    /// @inheritdoc IVault
    function getPoolPausedState(
        address pool
    ) external view withRegisteredPool(pool) returns (bool, uint256, uint256, address) {
        (bool paused, uint256 pauseWindowEndTime) = _getPoolPausedState(pool);

        return (paused, pauseWindowEndTime, pauseWindowEndTime + _vaultBufferPeriodDuration, _poolPauseManagers[pool]);
    }

    /// @dev Check both the flag and timestamp to determine whether the pool is paused.
    function _isPoolPaused(address pool) internal view returns (bool) {
        (bool paused, ) = _getPoolPausedState(pool);

        return paused;
    }

    /// @dev Lowest level routine that plucks only the minimum necessary parts from storage.
    function _getPoolPausedState(address pool) private view returns (bool, uint256) {
        (bool pauseBit, uint256 pauseWindowEndTime) = PoolConfigLib.getPoolPausedState(_poolConfig[pool]);

        // Use the Vault's buffer period.
        return (pauseBit && block.timestamp <= pauseWindowEndTime + _vaultBufferPeriodDuration, pauseWindowEndTime);
    }

    /// @inheritdoc IVault
    function pausePool(address pool) external withRegisteredPool(pool) onlyAuthenticatedPauser(pool) {
        _setPoolPaused(pool, true);
    }

    /// @inheritdoc IVault
    function unpausePool(address pool) external withRegisteredPool(pool) onlyAuthenticatedPauser(pool) {
        _setPoolPaused(pool, false);
    }

    function _setPoolPaused(address pool, bool pausing) internal {
        PoolConfig memory config = PoolConfigLib.toPoolConfig(_poolConfig[pool]);

        if (_isPoolPaused(pool)) {
            if (pausing) {
                // Already paused, and we're trying to pause it again.
                revert PoolPaused(pool);
            }

            // The pool can always be unpaused while it's paused.
            // When the buffer period expires, `_isPoolPaused` will return false, so we would be in the outside
            // else clause, where trying to unpause will revert unconditionally.
        } else {
            if (pausing) {
                // Not already paused; we can pause within the window.
                if (block.timestamp >= config.pauseWindowEndTime) {
                    revert PoolPauseWindowExpired(pool);
                }
            } else {
                // Not paused, and we're trying to unpause it.
                revert PoolNotPaused(pool);
            }
        }

        // Update poolConfig.
        config.isPoolPaused = pausing;
        _poolConfig[pool] = config.fromPoolConfig();

        emit PoolPausedStateChanged(pool, pausing);
    }

    /**
     * @dev Reverts if the pool is paused.
     * @param pool The pool
     */
    function _ensurePoolNotPaused(address pool) internal view {
        if (_isPoolPaused(pool)) {
            revert PoolPaused(pool);
        }
    }
}
