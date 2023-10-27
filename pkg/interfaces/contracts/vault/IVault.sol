// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBasePool } from "./IBasePool.sol";
import { Asset } from "../solidity-utils/misc/Asset.sol";
import { IAuthorizer } from "./IAuthorizer.sol";

/// @dev Represents a pool's callbacks.
struct PoolCallbacks {
    bool shouldCallAfterSwap;
    bool shouldCallBeforeAddLiquidity;
    bool shouldCallAfterAddLiquidity;
    bool shouldCallBeforeRemoveLiquidity;
    bool shouldCallAfterRemoveLiquidity;
}

struct LiquidityManagement {
    bool supportsAddLiquiditySingleTokenExactOut;
    bool supportsAddLiquidityUnbalanced;
    bool supportsAddLiquidityCustom;
    bool supportsRemoveLiquiditySingleTokenExactIn;
    bool supportsRemoveLiquidityUnbalanced;
    bool supportsRemoveLiquidityCustom;
}

struct LiquidityManagementDefaults {
    bool supportsAddLiquidityProportional;
    bool supportsRemoveLiquidityProportional;
}

/// @dev Represents a pool's configuration, including callbacks.
struct PoolConfig {
    bool isRegisteredPool;
    bool isInitializedPool;
    PoolCallbacks callbacks;
    LiquidityManagement liquidityManagement;
    LiquidityManagementDefaults liquidityManagementDefaults;
}

interface IVault {
    /*******************************************************************************
                        Pool Registration and Initialization
    *******************************************************************************/

    /**
     * @dev A pool has already been registered. `registerPool` may only be called once.
     * @param pool The already registered pool
     */
    error PoolAlreadyRegistered(address pool);

    /**
     * @dev A pool has already been initialized. `initialize` may only be called once.
     * @param pool The already initialized pool
     */
    error PoolAlreadyInitialized(address pool);

    /**
     * @dev A pool has not been registered.
     * @param pool The unregistered pool
     */
    error PoolNotRegistered(address pool);

    /**
     * @dev A referenced pool has not been initialized.
     * @param pool The uninitialized pool
     */
    error PoolNotInitialized(address pool);

    /// @dev Invalid tokens (e.g., zero) cannot be registered.
    error InvalidToken();

    /**
     * @dev A token was already registered (i.e., it is a duplicate in the pool).
     * @param token The duplicate token
     */
    error TokenAlreadyRegistered(IERC20 token);

    /// @dev The BPT amount involved in the operation is below the absolute minimum.
    error BptAmountBelowAbsoluteMin();

    /// @dev The token count is below the minimum allowed.
    error MinTokens();

    /// @dev The token count is above the maximum allowed.
    error MaxTokens();

    /**
     * @notice A Pool was registered by calling `registerPool`.
     * @param pool The pool being registered
     * @param factory The factory creating the pool
     * @param tokens The pool's tokens
     */
    event PoolRegistered(address indexed pool, address indexed factory, IERC20[] tokens);

    /**
     * @notice A Pool was initialized by calling `initialize`.
     * @param pool The pool being initialized
     */
    event PoolInitialized(address indexed pool);

    /**
     * @notice Pool balances have changed (e.g., after initialization, add/remove liquidity).
     * @param pool The pool being registered
     * @param liquidityProvider The user performing the operation
     * @param tokens The pool's tokens
     * @param deltas The amount each token changed
     */
    event PoolBalanceChanged(address indexed pool, address indexed liquidityProvider, IERC20[] tokens, int256[] deltas);

    /**
     * @notice Registers a pool, associating it with its factory and the tokens it manages.
     * @dev This function assumes the default proportional liquidity methods are supported.
     * @param factory The factory address associated with the pool being registered
     * @param tokens An array of token addresses the pool will manage
     * @param config Config for the pool
     * @param liquidityManagement Liquidity management flags with implemented methods
     */
    function registerPool(
        address factory,
        IERC20[] memory tokens,
        PoolCallbacks calldata config,
        LiquidityManagement calldata liquidityManagement
    ) external;

    /**
     * @notice Registers a pool, associating it with its factory and the tokens it manages.
     * @param factory The factory address associated with the pool being registered
     * @param tokens An array of token addresses the pool will manage
     * @param config Config for the pool
     * @param liquidityManagement Liquidity management flags with implemented methods
     * @param liquidityManagementDefaults Liquidity management flags for default, proportional methods
     */
    function registerPool(
        address factory,
        IERC20[] memory tokens,
        PoolCallbacks calldata config,
        LiquidityManagement calldata liquidityManagement,
        LiquidityManagementDefaults calldata liquidityManagementDefaults
    ) external;

    /**
     * @notice Initializes a registered pool by adding liquidity; mints BPT tokens for the first time in exchange.
     * @dev The initial liquidity should make the pool mint at least `_MINIMUM_BPT` tokens, otherwise the
     * initialization will fail. Besides the BPT minted to the given target address (`to`), `_MINIMUM_BPT` tokens are
     * minted to address(0).
     *
     * @param pool Address of the pool to initialize
     * @param to Address that will receive the output BPT
     * @param tokens tokens involved in the liquidity provision
     * @param maxAmountsIn Maximum amounts of input tokens
     * @param userData Additional (optional) data for the initialization
     * @return amountsIn Actual amounts of input tokens
     * @return bptAmountOut Output pool token amount
     */
    function initialize(
        address pool,
        address to,
        IERC20[] memory tokens,
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /**
     * @notice Checks whether a pool is registered.
     * @param pool Address of the pool to check
     * @return True if the pool is registered, false otherwise
     */
    function isRegisteredPool(address pool) external view returns (bool);

    /**
     * @notice Checks whether a pool is initialized.
     * @dev An initialized pool can be considered registered as well.
     * @param pool Address of the pool to check
     * @return True if the pool is initialized, false otherwise
     */
    function isInitializedPool(address pool) external view returns (bool);

    /**
     * @notice Gets tokens and their balances of a pool.
     * @param pool Address of the pool
     * @return tokens List of tokens in the pool
     * @return balances Corresponding balances of the tokens
     */
    function getPoolTokens(address pool) external view returns (IERC20[] memory tokens, uint256[] memory balances);

    /**
     * @notice Gets the configuration paramters of a pool.
     * @param pool Address of the pool
     * @return Pool configuration
     */
    function getPoolConfig(address pool) external view returns (PoolConfig memory);

    /**
     * @notice Get the minimum number of tokens in a pool.
     * @dev We expect the vast majority of pools to be 2-token.
     * @return The token count of a minimal pool
     */
    function getMinimumPoolTokens() external pure returns (uint256);

    /**
     * @notice Get the maximum number of tokens in a pool.
     * @return The token count of a minimal pool
     */
    function getMaximumPoolTokens() external pure returns (uint256);

    /*******************************************************************************
                                    MultiToken
    *******************************************************************************/

    /**
     * @notice Gets total supply of a given ERC20 token.
     * @param token Token's address
     * @return Total supply of the token
     */
    function totalSupply(address token) external view returns (uint256);

    /**
     * @notice Gets balance of an account for a given ERC20 token.
     * @param token Token's address
     * @param account Account's address
     * @return Balance of the account for the token
     */
    function balanceOf(address token, address account) external view returns (uint256);

    /**
     * @notice Gets allowance of a spender for a given ERC20 token and owner.
     * @param token Token's address
     * @param owner Owner's address
     * @param spender Spender's address
     * @return Amount of tokens the spender is allowed to spend
     */
    function allowance(address token, address owner, address spender) external view returns (uint256);

    /**
     * @notice Transfers pool token from owner to a recipient.
     * @dev Notice that the pool token address is not included in the params. This function is exclusively called by
     * the pool contract, so msg.sender is used as the token address.
     *
     * @param owner Owner's address
     * @param to Recipient's address
     * @param amount Amount of tokens to transfer
     * @return True if successful, false otherwise
     */
    function transfer(address owner, address to, uint256 amount) external returns (bool);

    /**
     * @notice Transfers pool token from a sender to a recipient using an allowance.
     * @dev Notice that the pool token address is not included in the params. This function is exclusively called by
     * the pool contract, so msg.sender is used as the token address.
     *
     * @param spender Address allowed to perform the transfer
     * @param from Sender's address
     * @param to Recipient's address
     * @param amount Amount of tokens to transfer
     * @return True if successful, false otherwise
     */
    function transferFrom(address spender, address from, address to, uint256 amount) external returns (bool);

    /**
     * @notice Approves a spender to spend pool tokens on behalf of sender.
     * @dev Notice that the pool token address is not included in the params. This function is exclusively called by
     * the pool contract, so msg.sender is used as the token address.
     *
     * @param owner Owner's address
     * @param spender Spender's address
     * @param amount Amount of tokens to approve
     * @return True if successful, false otherwise
     */
    function approve(address owner, address spender, uint256 amount) external returns (bool);

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /**
     * @dev Error indicating the sender is not the Vault (e.g., someone is trying to call a permissioned function).
     * @param sender The account attempting to call a permissioned function
     */
    error SenderIsNotVault(address sender);

    /// @dev The BPT amount requested from removing liquidity is above the maximum specified for the operation.
    error BptAmountAboveMax();

    /// @dev A transient accounting operation completed with outstanding token deltas.
    error BalanceNotSettled();

    /**
     * @dev In transient accounting, a handler is attempting to execute an operation out of order.
     * The caller address should equal the handler.
     * @param handler Address of the current handler being processed
     * @param caller Address of the caller (msg.sender)
     */
    error WrongHandler(address handler, address caller);

    /// @dev A user called a Vault function (swap, add/remove liquidity) outside the invoke context.
    error NoHandler();

    /**
     * @dev The caller attempted to access a handler at an invalid index.
     * @param index The invalid index
     */
    error HandlerOutOfBounds(uint256 index);

    /// @dev The pool has returned false to a callback, indicating the transaction should revert.
    error CallbackFailed();

    /// @dev An unauthorized Router tried to call a permissioned function (i.e., using the Vault's token allowance).
    error RouterNotTrusted();

    /**
     * @notice Invokes a callback on msg.sender with arguments provided in `data`.
     * @dev Callback is `transient`, meaning all balances for the caller have to be settled at the end.
     * @param data Contains function signature and args to be passed to the msg.sender
     * @return result Resulting data from the call
     */
    function invoke(bytes calldata data) external payable returns (bytes memory result);

    /**
     * @notice Settles deltas for a token.
     * @param token Token's address
     * @return paid Amount paid during settlement
     */
    function settle(IERC20 token) external returns (uint256 paid);

    /**
     * @notice Sends tokens to a recipient.
     * @param token Token's address
     * @param to Recipient's address
     * @param amount Amount of tokens to send
     */
    function wire(IERC20 token, address to, uint256 amount) external;

    /**
     * @notice Retrieves tokens from a sender.
     * @dev This function can transfer tokens from users using allowances granted to the Vault.
     * Only trusted routers should be permitted to invoke it. Untrusted routers should use `settle` instead.
     *
     * @param token Token's address
     * @param from Sender's address
     * @param amount Amount of tokens to retrieve
     */
    function retrieve(IERC20 token, address from, uint256 amount) external;

    /**
     * @notice Returns the address at the specified index of the _handlers array.
     * @param index The index of the handler's address to fetch
     * @return The address at the given index
     */
    function getHandler(uint256 index) external view returns (address);

    /**
     * @notice Returns the total number of handlers.
     * @return The number of handlers
     */
    function getHandlersCount() external view returns (uint256);

    /**
     *  @notice Returns the count of non-zero deltas.
     *  @return The current value of _nonzeroDeltaCount
     */
    function getNonzeroDeltaCount() external view returns (uint256);

    /**
     * @notice Retrieves the token delta for a specific user and token.
     * @dev This function allows reading the value from the `_tokenDeltas` mapping.
     * @param user The address of the user for whom the delta is being fetched
     * @param token The token for which the delta is being fetched
     * @return The delta of the specified token for the specified user
     */
    function getTokenDelta(address user, IERC20 token) external view returns (int256);

    /**
     * @notice Retrieves the reserve of a given token.
     * @param token The token for which to retrieve the reserve
     * @return The amount of reserves for the given token
     */
    function getTokenReserve(IERC20 token) external view returns (uint256);

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    /**
     * @dev The token list passed into an operation does not match the pool tokens in the pool.
     * @param pool Address of the pool
     * @param expectedToken The correct token at a given index in the pool
     * @param actualToken The actual token found at that index
     */
    error TokensMismatch(address pool, address expectedToken, address actualToken);

    /// @dev The user tried to swap zero tokens.
    error AmountGivenZero();

    /// @dev The user attempted to swap a token for itself.
    error CannotSwapSameToken();

    /// @dev The user attempted to swap a token not in the pool.
    error TokenNotRegistered();

    /// @dev Pool does not support adding liquidity proportionally.
    error DoesNotSupportAddLiquidityProportional(address pool);

    /// @dev Pool does not support adding liquidity with unbalanced tokens in.
    error DoesNotSupportAddLiquidityUnbalanced(address pool);

    /// @dev Pool does not support adding liquidity with a single asset, specifying exact pool tokens out.
    error DoesNotSupportAddLiquiditySingleTokenExactOut(address pool);

    /// @dev Pool does not support adding liquidity with a customized input.
    error DoesNotSupportAddLiquidityCustom(address pool);

    /**
     * @notice Adds liquidity to a pool.
     * @dev Caution should be exercised when adding liquidity because the Vault has the capability
     * to transfer tokens from any user, given that it holds all allowances.
     *
     * @param pool Address of the pool
     * @param to  Address of user to mint to
     * @param assets Assets involved in the liquidity
     * @param maxAmountsIn Maximum amounts of input assets
     * @param minBptAmountOut Minimum output pool token amount
     * @param kind Add liquidity kind
     * @param userData Additional (optional) user data
     * @return amountsIn Actual amounts of input assets
     * @return bptAmountOut Output pool token amount
     */
    function addLiquidity(
        address pool,
        address to,
        IERC20[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        IBasePool.AddLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    function addLiquidityProportional(
        address pool,
        address to,
        uint256 exactBptAmountOut
    ) external returns (uint256[] memory amountsIn);

    function addLiquidityUnbalanced(
        address pool,
        address to,
        uint256[] memory exactAmountsIn
    ) external returns (uint256 bptAmountOut);

    function addLiquiditySingleTokenExactOut(
        address pool,
        address to,
        IERC20 tokenIn,
        uint256 exactBptAmountOut
    ) external returns (uint256 amountIn);

    function addLiquidityCustom(
        address pool,
        address to,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    /// @dev Pool does not support removing liquidity proportionally.
    error DoesNotSupportRemoveLiquidityProportional(address pool);

    /// @dev Pool does not support removing liquidity with unbalanced tokens out.
    error DoesNotSupportRemoveLiquidityUnbalanced(address pool);

    /// @dev Pool does not support removing liquidity with a single asset, specifying exact pool tokens in.
    error DoesNotSupportRemoveLiquiditySingleTokenExactIn(address pool);

    /// @dev Pool does not support removing liquidity with a customized input.
    error DoesNotSupportRemoveLiquidityCustom(address pool);

    /**
     * @notice Removes liquidity from a pool.
     * @dev Trusted routers can burn pool tokens belonging to any user and require no prior approval from the user.
     * Untrusted routers require prior approval from the user. This is the only function allowed to call
     * _queryModeBalanceIncrease (and only in a query context).
     *
     * @param pool Address of the pool
     * @param from Address of user to burn from
     * @param assets Assets involved in the liquidity removal
     * @param minAmountsOut Minimum amounts of output assets
     * @param maxBptAmountIn Input pool token amount
     * @param kind Remove liquidity kind
     * @param userData Additional (optional) user data
     * @return amountsOut Actual amounts of output assets
     * @return bptAmountIn Actual amount of BPT burnt
     */
    function removeLiquidity(
        address pool,
        address from,
        IERC20[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 maxBptAmountIn,
        IBasePool.RemoveLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut, uint256 bptAmountIn);

    function removeLiquidityProportional(
        address pool,
        address from,
        uint256 exactBptAmountIn
    ) external returns (uint256[] memory amountsOut);

    function removeLiquiditySingleTokenExactIn(
        address pool,
        address from,
        IERC20 tokenOut,
        uint256 exactBptAmountIn
    ) external returns (uint256 amountOut);

    function removeLiquidityCustom(
        address pool,
        address from,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut, uint256 bptAmountIn, bytes memory returnData);

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    /**
     * @dev Data for a swap operation.
     * @param kind Type of swap (Given In or Given Out)
     * @param pool The pool with the tokens being swapped
     * @param tokenIn The token entering the Vault (balance increases)
     * @param tokenOut The token leaving the Vault (balance decreases)
     * @param amountGiven Amount specified for tokenIn or tokenOut (depending on the type of swap)
     * @param userData Additional (optional) user data
     */
    struct SwapParams {
        SwapKind kind;
        address pool;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountGiven;
        bytes userData;
    }

    /**
     * @notice A swap has occurred.
     * @param pool The pool with the tokens being swapped
     * @param tokenIn The token entering the Vault (balance increases)
     * @param tokenOut The token leaving the Vault (balance decreases)
     * @param amountIn Number of tokenIn tokens
     * @param amountOut Number of tokenOut tokens
     */
    event Swap(
        address indexed pool,
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /**
     * @notice Swaps tokens based on provided parameters.
     * @param params Parameters for the swap (see above for struct definition)
     * @return amountCalculated Calculated swap amount
     * @return amountIn Amount of input tokens for the swap
     * @return amountOut Amount of output tokens from the swap
     */
    function swap(
        SwapParams memory params
    ) external returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut);

    /*******************************************************************************
                                    Queries
    *******************************************************************************/

    /// @dev A user tried to execute a query operation when they were disabled.
    error QueriesDisabled();

    /**
     * @notice Invokes a callback on msg.sender with arguments provided in `data`.
     * @dev Used to query a set of operations on the Vault. Only off-chain eth_call are allowed,
     * anything else will revert.
     *
     * Allows querying any operation on the Vault that has the `withHandler` modifier.
     *
     * Allows the external calling of a function via the Vault contract to
     * access Vault's functions guarded by `withHandler`.
     * `transient` modifier ensuring balances changes within the Vault are settled.
     *
     * @param data Contains function signature and args to be passed to the msg.sender
     * @return result Resulting data from the call
     */
    function quote(bytes calldata data) external payable returns (bytes memory result);

    /// @notice Disables queries functionality on the Vault. Can be called only by governance.
    function disableQuery() external;

    /**
     * @notice Checks if the queries enabled on the Vault.
     * @return If true, then queries are disabled
     */
    function isQueryDisabled() external view returns (bool);

    /*******************************************************************************
                                Authentication
    *******************************************************************************/

    /**
     * @notice A new authorizer is set by `setAuthorizer`.
     * @param newAuthorizer The address of the new authorizer
     */
    event AuthorizerChanged(IAuthorizer indexed newAuthorizer);

    /**
     * @notice Returns the Vault's Authorizer.
     * @return Address of the authorizer
     */
    function getAuthorizer() external view returns (IAuthorizer);

    /**
     * @notice Sets a new Authorizer for the Vault.
     * @dev The caller must be allowed by the current Authorizer to do this.
     * Emits an `AuthorizerChanged` event.
     */
    function setAuthorizer(IAuthorizer newAuthorizer) external;
}
