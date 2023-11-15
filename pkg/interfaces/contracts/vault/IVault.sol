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
    bool supportsAddLiquidityProportional;
    bool supportsAddLiquiditySingleTokenExactOut;
    bool supportsAddLiquidityUnbalanced;
    bool supportsAddLiquidityCustom;
    bool supportsRemoveLiquidityProportional;
    bool supportsRemoveLiquiditySingleTokenExactIn;
    bool supportsRemoveLiquiditySingleTokenExactOut;
    bool supportsRemoveLiquidityCustom;
}

/// @dev Represents a pool's configuration, including callbacks.
struct PoolConfig {
    bool isRegisteredPool;
    bool isInitializedPool;
    bool hasDynamicSwapFee;
    uint64 staticSwapFeePercentage; // stores an 18-decimal FP value (max FixedPoint.ONE)
    uint24 tokenDecimalDiffs; // stores 18-(token decimals), for each token
    PoolCallbacks callbacks;
    LiquidityManagement liquidityManagement;
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
     * @param liquidityManagement Supported liquidity management callback flags
     */
    event PoolRegistered(
        address indexed pool,
        address indexed factory,
        IERC20[] tokens,
        PoolCallbacks callbacks,
        LiquidityManagement liquidityManagement
    );

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
     * @dev This version of the function assumes the default proportional liquidity methods are supported.
     * @param factory The factory address associated with the pool being registered
     * @param tokens An array of token addresses the pool will manage
     * @param config Flags indicating which callbacks the pool supports
     * @param liquidityManagement Liquidity management flags with implemented methods
     */
    function registerPool(
        address factory,
        IERC20[] memory tokens,
        PoolCallbacks calldata config,
        LiquidityManagement calldata liquidityManagement
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
     * @param exactAmountsIn Exact amounts of input tokens
     * @param userData Additional (optional) data for the initialization
     * @return bptAmountOut Output pool token amount
     */
    function initialize(
        address pool,
        address to,
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

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
     * @notice Gets the tokens registered to a pool.
     * @param pool Address of the pool
     * @return tokens List of tokens in the pool
     */
    function getPoolTokens(address pool) external view returns (IERC20[] memory);

    /**
     * @notice Gets the raw data for a pool: tokens, raw balances, scaling factors.
     * @dev TODO Add rates when we have them.
     * @return tokens Tokens registered to the pool
     * @return rawBalances Corresponding raw balances of the tokens
     * @return scalingFactors Corresponding scalingFactors of the tokens
     */
    function getPoolTokenInfo(address pool) external view returns (IERC20[] memory, uint256[] memory, uint256[] memory);

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

    enum AddLiquidityKind {
        PROPORTIONAL,
        UNBALANCED,
        SINGLE_TOKEN_EXACT_OUT,
        CUSTOM
    }

    /// @dev Add liquidity kind not supported.
    error InvalidAddLiquidityKind();

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

    /**
     * @notice Adds liquidity to a pool.
     * @dev Caution should be exercised when adding liquidity because the Vault has the capability
     * to transfer tokens from any user, given that it holds all allowances.
     *
     * @param pool Address of the pool
     * @param to  Address of user to mint to
     * @param maxAmountsIn Maximum amounts of input tokens
     * @param minBptAmountOut Minimum amount of output pool tokens
     * @param kind Add liquidity kind
     * @param userData Additional (optional) user data
     * @return amountsIn Actual amounts of input assets
     * @return bptAmountOut Output pool token amount
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function addLiquidity(
        address pool,
        address to,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        AddLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    enum RemoveLiquidityKind {
        PROPORTIONAL,
        SINGLE_TOKEN_EXACT_IN,
        SINGLE_TOKEN_EXACT_OUT,
        CUSTOM
    }

    /// @dev Remove liquidity kind not supported.
    error InvalidRemoveLiquidityKind();

    /**
     * @notice Removes liquidity from a pool.
     * @dev Trusted routers can burn pool tokens belonging to any user and require no prior approval from the user.
     * Untrusted routers require prior approval from the user. This is the only function allowed to call
     * _queryModeBalanceIncrease (and only in a query context).
     *
     * @param pool Address of the pool
     * @param from Address of user to burn from
     * @param maxBptAmountIn Maximum amount of input pool tokens
     * @param minAmountsOut Minimum amounts of output tokens
     * @param kind Remove liquidity kind
     * @param userData Additional (optional) user data
     * @return bptAmountIn Actual amount of BPT burnt
     * @return amountsOut Actual amounts of output assets
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function removeLiquidity(
        address pool,
        address from,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        RemoveLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData);

    /**
     * @notice Remove liquidity from a pool specifying exact pool tokens in, with proportional token amounts out.
     * The request is implemented by the Vault without any interaction with the pool, ensuring that
     * it works the same for all pools, and cannot be disabled by a new pool type.
     *
     * @param pool Address of the pool
     * @param from Address of user to burn pool tokens from
     * @param exactBptAmountIn Input pool token amount
     * @return amountsOut Actual calculated amounts of output tokens
     */
    function removeLiquidityRecovery(
        address pool,
        address from,
        uint256 exactBptAmountIn
    ) external returns (uint256[] memory amountsOut);

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
     * @param rawAmountGiven Amount specified for tokenIn or tokenOut (depending on the type of swap)
     * @param userData Additional (optional) user data
     */
    struct SwapParams {
        SwapKind kind;
        address pool;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 rawAmountGiven;
        bytes userData;
    }

    /**
     * @notice A swap has occurred.
     * @param pool The pool with the tokens being swapped
     * @param tokenIn The token entering the Vault (balance increases)
     * @param tokenOut The token leaving the Vault (balance decreases)
     * @param amountIn Number of tokenIn tokens
     * @param amountOut Number of tokenOut tokens
     * @param swapFeeAmount Swap fee amount paid in token out
     */
    event Swap(
        address indexed pool,
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 swapFeeAmount
    );

    /**
     * @notice Swaps tokens based on provided parameters.
     * @dev All parameters are given in raw token decimal encoding.
     * @param params Parameters for the swap (see above for struct definition)
     * @return rawAmountCalculated Calculated swap amount
     * @return rawAmountIn Amount of input tokens for the swap
     * @return rawAmountOut Amount of output tokens from the swap
     */
    function swap(
        SwapParams memory params
    ) external returns (uint256 rawAmountCalculated, uint256 rawAmountIn, uint256 rawAmountOut);

    /*******************************************************************************
                                   Fees
    *******************************************************************************/

    /// @dev Error raised when the protocol swap fee percentage exceeds the maximum allowed value.
    error ProtocolSwapFeePercentageTooHigh();

    /// @dev Error raised when the swap fee percentage exceeds the maximum allowed value.
    error SwapFeePercentageTooHigh();

    /**
     * @notice Sets a new swap fee percentage for the protocol.
     * @param newSwapFeePercentage The new swap fee percentage to be set
     */
    function setProtocolSwapFeePercentage(uint256 newSwapFeePercentage) external;

    /**
     * @notice Emitted when the protocol swap fee percentage is updated.
     * @param swapFeePercentage The updated protocol swap fee percentage
     */
    event ProtocolSwapFeePercentageChanged(uint256 indexed swapFeePercentage);

    /**
     * @notice Retrieves the current protocol swap fee percentage.
     * @return The current protocol swap fee percentage
     */
    function getProtocolSwapFeePercentage() external view returns (uint256);

    /**
     * @notice Returns the accumulated swap fee in `token` collected by the protocol.
     * @param token The address of the token in which fees have been accumulated
     * @return The total amount of fees accumulated in the specified token
     */
    function getProtocolSwapFee(address token) external view returns (uint256);

    /**
     * @notice Collects accumulated protocol fees for the specified array of tokens.
     * @dev Fees are sent to msg.sender.
     * @param tokens An array of token addresses for which the fees should be collected
     */
    function collectProtocolFees(IERC20[] calldata tokens) external;

    /**
     * @notice Logs the collection of fees in a specific token and amount.
     * @param token The token in which the fee has been collected
     * @param amount The amount of the token collected as fees
     */
    event ProtocolFeeCollected(IERC20 indexed token, uint256 indexed amount);

    /**
     * @notice Assigns a new static swap fee percentage to the specified pool.
     * @param pool The address of the pool for which the static swap fee will be changed
     * @param swapFeePercentage The new swap fee percentage to apply to the pool
     */
    function setStaticSwapFeePercentage(address pool, uint256 swapFeePercentage) external;

    /**
     * @notice Emitted when the swap fee percentage of a pool is updated.
     * @param swapFeePercentage The new swap fee percentage for the pool
     */
    event SwapFeePercentageChanged(address indexed pool, uint256 indexed swapFeePercentage);

    /**
     * @notice Fetches the static swap fee percentage for a given pool.
     * @param pool The address of the pool whose static swap fee percentage is being queried
     * @return The current static swap fee percentage for the specified pool
     */
    function getStaticSwapFeePercentage(address pool) external view returns (uint256);

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

    /*******************************************************************************
                                Miscellaneous
    *******************************************************************************/

    /// @dev Optional User Data should be empty in the current add / remove liquidity kind.
    error UserDataNotSupported();
}
