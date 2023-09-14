// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/token/IERC20MultiToken.sol";
import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { ReentrancyGuard } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import { TemporarilyPausable } from "@balancer-labs/v3-solidity-utils/contracts/helpers/TemporarilyPausable.sol";
import { Asset, AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { ERC20MultiToken } from "@balancer-labs/v3-solidity-utils/contracts/token/ERC20MultiToken.sol";

import { PoolConfigBits, PoolConfigLib } from "./lib/PoolConfigLib.sol";

contract Vault is IVault, IVaultErrors, ERC20MultiToken, ReentrancyGuard, TemporarilyPausable {
    using EnumerableMap for EnumerableMap.IERC20ToUint256Map;
    using InputHelpers for uint256;
    using AssetHelpers for *;
    using ArrayHelpers for uint256[];
    using Address for *;
    using SafeERC20 for IERC20;
    using SafeCast for *;
    using PoolConfigLib for PoolConfig;

    // Registry of pool configs.
    mapping(address => PoolConfigBits) internal _poolConfig;

    // Pool -> (token -> balance): Pool's ERC20 tokens balances stored at the Vault.
    mapping(address => EnumerableMap.IERC20ToUint256Map) internal _poolTokenBalances;

    /// @notice List of handlers. It is non-empty only during `invoke` calls.
    address[] private _handlers;
    /// @notice The total number of nonzero deltas over all active + completed lockers.
    /// @dev It is non-zero only during `invoke` calls.
    uint256 private _nonzeroDeltaCount;
    /// @notice Represents the asset due/owed to each handler.
    /// @dev Must all net to zero when the last handler is released.
    mapping(address => mapping(IERC20 => int256)) private _tokenDeltas;
    /// @notice Represents the total reserve of each ERC20 token.
    /// @dev It should be always equal to `token.balanceOf(vault)`, with only
    /// exception being during the `invoke` call.
    mapping(IERC20 => uint256) private _tokenReserves;

    /// @notice If set to true, disables query functionality of the Vault. Can be modified only by governance.
    bool private _isQueryDisabled;

    constructor(uint256 pauseWindowDuration, uint256 bufferPeriodDuration)
        TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration)
    {
        // solhint-disable-previous-line no-empty-blocks
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

    /**
     * @inheritdoc IVault
     * @dev Allows the external calling of a function via the Vault contract to
     * access Vault's functions guarded by `withHandler`.
     * `transient` modifier ensuring balances changes within the Vault are settled.
     */
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
        _accountDelta(token, -paid.toInt256(), msg.sender);
    }

    /// @inheritdoc IVault
    function wire(
        IERC20 token,
        address to,
        uint256 amount
    ) public nonReentrant withHandler {
        // effects
        _accountDelta(token, amount.toInt256(), msg.sender);
        _tokenReserves[token] -= amount;
        // interactions
        token.safeTransfer(to, amount);
    }

    /// @inheritdoc IVault
    function mint(
        IERC20 token,
        address to,
        uint256 amount
    ) public nonReentrant withHandler {
        _accountDelta(token, amount.toInt256(), msg.sender);
        _mint(address(token), to, amount);
    }

    /// @inheritdoc IVault
    function retrieve(
        IERC20 token,
        address from,
        uint256 amount
    ) public nonReentrant withHandler {
        // effects
        _accountDelta(token, -(amount.toInt256()), msg.sender);
        _tokenReserves[token] += amount;
        // interactions
        token.safeTransferFrom(from, address(this), amount);
    }

    /// @inheritdoc IVault
    function burn(
        IERC20 token,
        address owner,
        uint256 amount
    ) public nonReentrant withHandler {
        _spendAllowance(address(token), owner, address(this), amount);
        _burn(address(token), owner, amount);
        _accountDelta(token, -(amount.toInt256()), msg.sender);
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
    function _accountDelta(
        IERC20 token,
        int256 delta,
        address handler
    ) internal {
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

    /**
     * @dev Ensure that only static calls are made to the functions with this modifier.
     * A static call is one where `tx.origin` equals 0x0 for most implementations.
     * More https://twitter.com/0xkarmacoma/status/1493380279309717505
     */
    modifier query() {
        // Check if the transaction initiator is different from the 0x0.
        // If so, it's not a eth_call and we revert.
        // https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_call
        if (tx.origin != address(0)) {
            // solhint-disable-previous-line avoid-tx-origin
            revert NotStaticCall();
        }

        if (_isQueryDisabled) {
            revert QueriesDisabled();
        }

        // Add the current handler to the list so `withHandler` would not revert
        _handlers.push(msg.sender);
        _;
    }

    /**
     * @inheritdoc IVault
     * @dev Allows to query any operations on the Vault with `withHandler` modifier.
     */
    function quote(bytes calldata data) external payable query returns (bytes memory result) {
        // Forward the incoming call to the original sender of this transaction.
        return (msg.sender).functionCallWithValue(data, msg.value);
    }

    /**
     * @inheritdoc IVault
     */
    function disableQuery() external {
        // TODO: Only governance can call this function.
        _isQueryDisabled = true;
    }

    /**
     * @inheritdoc IVault
     */
    function isQueryDisabled() external view returns (bool) {
        return _isQueryDisabled;
    }

    /*******************************************************************************
                                    ERC20 Tokens
    *******************************************************************************/

    /// @inheritdoc IERC20MultiToken
    function totalSupply(address token) external view returns (uint256) {
        return _totalSupply(token);
    }

    /// @inheritdoc IERC20MultiToken
    function balanceOf(address token, address account) external view returns (uint256) {
        return _balanceOf(token, account);
    }

    /// @inheritdoc IERC20MultiToken
    function allowance(
        address token,
        address owner,
        address spender
    ) external view returns (uint256) {
        return _allowance(token, owner, spender);
    }

    /// @inheritdoc IERC20MultiToken
    function transferWith(
        address owner,
        address to,
        uint256 amount
    ) external returns (bool) {
        _transfer(msg.sender, owner, to, amount);
        return true;
    }

    /// @inheritdoc IERC20MultiToken
    function transfer(
        address token,
        address to,
        uint256 amount
    ) external returns (bool) {
        _transfer(token, msg.sender, to, amount);
        return true;
    }

    /// @inheritdoc IERC20MultiToken
    function approveWith(
        address owner,
        address spender,
        uint256 amount
    ) external returns (bool) {
        _approve(msg.sender, owner, spender, amount);
        return true;
    }

    /// @inheritdoc IERC20MultiToken
    function approve(
        address token,
        address spender,
        uint256 amount
    ) external returns (bool) {
        _approve(token, msg.sender, spender, amount);
        return true;
    }

    /// @inheritdoc IERC20MultiToken
    function transferFromWith(
        address spender,
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        _spendAllowance(msg.sender, from, spender, amount);
        _transfer(msg.sender, from, to, amount);
        return true;
    }

    /// @inheritdoc IERC20MultiToken
    function transferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        _spendAllowance(token, from, msg.sender, amount);
        _transfer(token, from, to, amount);
        return true;
    }

    /*******************************************************************************
                                          Swaps
    *******************************************************************************/

    /// @inheritdoc IVault
    function swap(SwapParams memory params)
        public
        whenNotPaused
        withHandler
        returns (
            uint256 amountCalculated,
            uint256 amountIn,
            uint256 amountOut
        )
    {
        if (params.amountGiven == 0) {
            revert AmountInZero();
        }

        if (params.tokenIn == params.tokenOut) {
            revert CannotSwapSameToken();
        }

        // We access both token indexes without checking existence, because we will do it manually immediately after.
        EnumerableMap.IERC20ToUint256Map storage poolBalances = _poolTokenBalances[params.pool];
        uint256 indexIn = poolBalances.unchecked_indexOf(params.tokenIn);
        uint256 indexOut = poolBalances.unchecked_indexOf(params.tokenOut);

        if (indexIn == 0 || indexOut == 0) {
            // The tokens might not be registered because the Pool itself is not registered. We check this to provide a
            // more accurate revert reason.
            _ensureRegisteredPool(params.pool);
            revert TokenNotRegistered();
        }

        // EnumerableMap stores indices *plus one* to use the zero index as a sentinel value - because these are valid,
        // we can undo this.
        indexIn -= 1;
        indexOut -= 1;

        uint256 tokenInBalance;
        uint256 tokenOutBalance;

        uint256[] memory currentBalances = new uint256[](poolBalances.length());

        for (uint256 i = 0; i < poolBalances.length(); i++) {
            // Because the iteration is bounded by `tokenAmount`, and no tokens are registered or deregistered here, we
            // know `i` is a valid token index and can use `unchecked_valueAt` to save storage reads.
            uint256 balance = poolBalances.unchecked_valueAt(i);

            currentBalances[i] = balance;

            if (i == indexIn) {
                tokenInBalance = balance;
            } else if (i == indexOut) {
                tokenOutBalance = balance;
            }
        }

        // Perform the swap request callback and compute the new balances for 'token in' and 'token out' after the swap
        amountCalculated = IBasePool(params.pool).onSwap(
            IBasePool.SwapParams({
                kind: params.kind,
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                amountGiven: params.amountGiven,
                balances: currentBalances,
                indexIn: indexIn,
                indexOut: indexOut,
                sender: msg.sender,
                userData: params.userData
            })
        );

        (amountIn, amountOut) = params.kind == SwapKind.GIVEN_IN
            ? (params.amountGiven, amountCalculated)
            : (amountCalculated, params.amountGiven);

        tokenInBalance = tokenInBalance + amountIn;
        tokenOutBalance = tokenOutBalance - amountOut;

        // Because no tokens were registered or deregistered between now or when we retrieved the indexes for
        // 'token in' and 'token out', we can use `unchecked_setAt` to save storage reads.
        poolBalances.unchecked_setAt(indexIn, tokenInBalance);
        poolBalances.unchecked_setAt(indexOut, tokenOutBalance);

        // Account amountIn of tokenIn
        _accountDelta(params.tokenIn, int256(amountIn), msg.sender);
        // Account amountOut of tokenOut
        _accountDelta(params.tokenOut, -int256(amountOut), msg.sender);

        if (_poolConfig[params.pool].shouldCallAfterSwap() == true) {
            if (
                IBasePool(params.pool).onAfterSwap(
                    IBasePool.SwapParams({
                        kind: params.kind,
                        tokenIn: params.tokenIn,
                        tokenOut: params.tokenOut,
                        amountGiven: params.amountGiven,
                        balances: currentBalances,
                        indexIn: indexIn,
                        indexOut: indexOut,
                        sender: msg.sender,
                        userData: params.userData
                    }),
                    amountCalculated
                ) == false
            ) {
                revert HookCallFailed();
            }
        }

        emit Swap(params.pool, params.tokenIn, params.tokenOut, amountIn, amountOut);
    }

    /*******************************************************************************
                                    Pool Registration
    *******************************************************************************/

    /**
     * @dev The function is designed to be called by a pool itself. The function will register the pool,
     *      setting its tokens with an initial balance of zero. The function also checks for valid token addresses
     *      and ensures that the pool and tokens aren't already registered.
     *      Emits a `PoolRegistered` event upon successful registration.
     * @inheritdoc IVault
     */
    function registerPool(
        address factory,
        IERC20[] memory tokens,
        PoolConfig calldata config
    ) external nonReentrant whenNotPaused {
        _registerPool(factory, tokens, config);
    }

    /// @inheritdoc IVault
    function isRegisteredPool(address pool) external view returns (bool) {
        return _isRegisteredPool(pool);
    }

    /// @inheritdoc IVault
    function getPoolConfig(address pool) external view returns (PoolConfig memory) {
        return _poolConfig[pool].toPoolConfig();
    }

    /// @inheritdoc IVault
    function getPoolTokens(address pool)
        external
        view
        withRegisteredPool(pool)
        returns (IERC20[] memory tokens, uint256[] memory balances)
    {
        return _getPoolTokens(pool);
    }

    /// @dev Emitted when a Pool is registered by calling `registerPool`.
    event PoolRegistered(address indexed pool, address indexed factory, IERC20[] tokens);

    /// @dev Reverts unless `pool` corresponds to a registered Pool.
    modifier withRegisteredPool(address pool) {
        _ensureRegisteredPool(pool);
        _;
    }

    /// @dev Reverts unless `pool` corresponds to a registered Pool.
    function _ensureRegisteredPool(address pool) internal view {
        if (!_isRegisteredPool(pool)) {
            revert PoolNotRegistered(pool);
        }
    }

    /// @dev See `registerPool`
    function _registerPool(
        address factory,
        IERC20[] memory tokens,
        PoolConfig memory config
    ) internal {
        address pool = msg.sender;

        // Ensure the pool isn't already registered
        if (_isRegisteredPool(pool)) {
            revert PoolAlreadyRegistered(pool);
        }

        // Retrieve or create the pool's token balances mapping
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];

            // Ensure that the token address is valid
            if (token == IERC20(address(0))) {
                revert InvalidToken();
            }

            // Register the token with an initial balance of zero.
            // Note: EnumerableMaps require an explicit initial value when creating a key-value pair.
            bool added = poolTokenBalances.set(tokens[i], 0);

            // Ensure the token isn't already registered for the pool
            if (!added) {
                revert TokenAlreadyRegistered(tokens[i]);
            }
        }

        // Store config and mark the pool as registered
        config.isRegisteredPool = true;
        _poolConfig[pool] = config.fromPoolConfig();

        // Emit an event to log the pool registration
        emit PoolRegistered(pool, factory, tokens);
    }

    /// @dev See `isRegisteredPool`
    function _isRegisteredPool(address pool) internal view returns (bool) {
        return _poolConfig[pool].isPoolRegistered();
    }

    /**
     * @notice Fetches the tokens and their corresponding balances for a given pool.
     * @dev Utilizes an enumerable map to obtain pool token balances.
     * The function is structured to minimize storage reads by leveraging the `unchecked_at` method.
     *
     * @param pool The address of the pool for which tokens and balances are to be fetched.
     * @return tokens An array of token addresses.
     * @return balances An array of corresponding token balances.
     */
    function _getPoolTokens(address pool) internal view returns (IERC20[] memory tokens, uint256[] memory balances) {
        // Retrieve the mapping of tokens and their balances for the specified pool.
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];

        // Initialize arrays to store tokens and their balances based on the number of tokens in the pool.
        tokens = new IERC20[](poolTokenBalances.length());
        balances = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length,
            // we can safely use `unchecked_at`. This ensures that `i` is a valid token index and minimizes
            // storage reads.
            (tokens[i], balances[i]) = poolTokenBalances.unchecked_at(i);
        }
    }

    /*******************************************************************************
                                    Pools
    *******************************************************************************/

    /// @inheritdoc IVault
    function initialize(
        address pool,
        IERC20[] memory tokens,
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) external
        withHandler
        whenNotPaused
        withRegisteredPool(pool)
        returns (uint256[] memory amountsIn, uint256 bptAmountOut) {

        InputHelpers.ensureInputLengthMatch(tokens.length, maxAmountsIn.length);

         _validateTokensAndGetBalances(pool, tokens);

        ( bptAmountOut, amountsIn) = IBasePool(pool).onInitialize(
            amountsIn,
            userData
        );

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amountIn = amountsIn[i];
            if (amountIn > maxAmountsIn[i]) {
                revert JoinAboveMax();
            }

            // Debit of token[i] for amountIn
            _accountDelta(tokens[i], int256(amountIn), msg.sender);
        }

        // Store the new Pool balances.
        _setPoolBalances(pool, amountsIn);

        // Credit bptAmountOut of pool tokens
        _accountDelta(IERC20(pool), -int256(bptAmountOut), msg.sender);

        emit PoolBalanceChanged(pool, msg.sender, tokens, amountsIn.unsafeCastToInt256(true));
    }


    /// @inheritdoc IVault
    function addLiquidity(
        address pool,
        IERC20[] memory tokens,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        IBasePool.AddLiquidityKind kind,
        bytes memory userData
    )
        external
        withHandler
        whenNotPaused
        withRegisteredPool(pool)
        returns (uint256[] memory amountsIn, uint256 bptAmountOut)
    {
        InputHelpers.ensureInputLengthMatch(tokens.length, maxAmountsIn.length);

        // We first check that the caller passed the Pool's registered tokens in the correct order
        // and retrieve the current balance for each.
        uint256[] memory balances = _validateTokensAndGetBalances(pool, tokens);

        // The bulk of the work is done here: the corresponding Pool hook is called
        // its final balances are computed
        (amountsIn, bptAmountOut) = IBasePool(pool).onAddLiquidity(
            msg.sender,
            balances,
            maxAmountsIn,
            minBptAmountOut,
            kind,
            userData
        );

        if (bptAmountOut < minBptAmountOut) {
            revert BtpAmountBelowMin();
        }

        uint256[] memory finalBalances = new uint256[](balances.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amountIn = amountsIn[i];
            if (amountIn > maxAmountsIn[i]) {
                revert JoinAboveMax();
            }

            // Debit of token[i] for amountIn
            _accountDelta(tokens[i], int256(amountIn), msg.sender);

            finalBalances[i] += amountIn;
        }

        // All that remains is storing the new Pool balances.
        _setPoolBalances(pool, finalBalances);

        // Credit bptAmountOut of pool tokens
        _accountDelta(IERC20(pool), -int256(bptAmountOut), msg.sender);

        if (_poolConfig[pool].shouldCallAfterAddLiquidity() == true) {
            if (
                IBasePool(pool).onAfterAddLiquidity(
                    msg.sender,
                    balances,
                    maxAmountsIn,
                    userData,
                    amountsIn,
                    bptAmountOut
                ) == false
            ) {
                revert HookCallFailed();
            }
        }

        emit PoolBalanceChanged(pool, msg.sender, tokens, amountsIn.unsafeCastToInt256(true));
    }

    /// @inheritdoc IVault
    function removeLiquidity(
        address pool,
        IERC20[] memory tokens,
        uint256[] memory minAmountsOut,
        uint256 maxBptAmountIn,
        IBasePool.RemoveLiquidityKind kind,
        bytes memory userData
    )
        external
        whenNotPaused
        nonReentrant
        withRegisteredPool(pool)
        returns (uint256[] memory amountsOut, uint256 bptAmountIn)
    {
        InputHelpers.ensureInputLengthMatch(tokens.length, minAmountsOut.length);

        // We first check that the caller passed the Pool's registered tokens in the correct order, and retrieve the
        // current balance for each.
        uint256[] memory balances = _validateTokensAndGetBalances(pool, tokens);

        // The bulk of the work is done here: the corresponding Pool hook is called, its final balances are computed
        (amountsOut, bptAmountIn) = IBasePool(pool).onRemoveLiquidity(
            msg.sender,
            balances,
            minAmountsOut,
            maxBptAmountIn,
            kind,
            userData
        );

        if (bptAmountIn > maxBptAmountIn) {
            revert BtpAmountAboveMax();
        }

        uint256[] memory finalBalances = new uint256[](balances.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amountOut = amountsOut[i];
            if (amountOut < minAmountsOut[i]) {
                revert ExitBelowMin();
            }
            // Credit token[i] for amountIn
            _accountDelta(tokens[i], -int256(amountOut), msg.sender);

            // Compute the new Pool balances. A Pool's token balance always decreases after an exit (potentially by 0).
            finalBalances[i] = balances[i] - amountOut;
        }

        // All that remains is storing the new Pool balances.
        _setPoolBalances(pool, finalBalances);

        // Debit bptAmountOut of pool tokens
        _accountDelta(IERC20(pool), int256(bptAmountIn), msg.sender);

        if (_poolConfig[pool].shouldCallAfterRemoveLiquidity() == true) {
            if (
                IBasePool(pool).onAfterRemoveLiquidity(
                    msg.sender,
                    balances,
                    minAmountsOut,
                    bptAmountIn,
                    userData,
                    amountsOut
                ) == false
            ) {
                revert HookCallFailed();
            }
        }

        emit PoolBalanceChanged(
            pool,
            msg.sender,
            tokens,
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
     *
     * `expectedTokens` must exactly equal the token array returned by `getPoolTokens`: both arrays must have the same
     * length, elements and order. Additionally, the Pool must have at least one registered token.
     */
    function _validateTokensAndGetBalances(address pool, IERC20[] memory expectedTokens)
        private
        view
        returns (uint256[] memory)
    {
        (IERC20[] memory actualTokens, uint256[] memory balances) = _getPoolTokens(pool);
        InputHelpers.ensureInputLengthMatch(actualTokens.length, expectedTokens.length);
        if (actualTokens.length == 0) {
            revert PoolHasNoTokens(pool);
        }

        for (uint256 i = 0; i < actualTokens.length; ++i) {
            if (actualTokens[i] != expectedTokens[i]) {
                revert TokensMismatch(address(actualTokens[i]), address(expectedTokens[i]));
            }
        }

        return balances;
    }
}
