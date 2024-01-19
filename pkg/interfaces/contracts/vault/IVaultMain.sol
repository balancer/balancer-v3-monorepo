// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthorizer } from "./IAuthorizer.sol";
import { IRateProvider } from "./IRateProvider.sol";
import "./VaultTypes.sol";

interface IVaultMain {
    /*******************************************************************************
                        Pool Registration and Initialization
    *******************************************************************************/

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
     * @notice Register a wrapped token buffer.
     * @dev We are assuming wrapped token addresses are unique (i.e., they are not upgradeable in place,
     * which would be insecure for depositors). Each wrapped token therefore unique describes a buffer,
     * since the base token is specified by IERC4626, and it is its own rate provider.
     * This is a permissioned function.
     *
     * @param wrappedToken The wrapped token associated with the new buffer.
     */
    function registerBuffer(address wrappedToken) external;

    /**
     * @dev Emitted on creation of a new wrapped token buffer.
     * @param baseToken The base ERC20 token
     * @param wrappedToken THe wrapped ERC4626 token
     */
    event WrappedTokenBufferRegistered(address indexed baseToken, address indexed wrappedToken);

    /**
     * @notice Get the current rate of a wrapped token buffer.
     * @dev Reverts if the buffer does not exist.
     * @param wrappedToken The IERC4626 wrapped token
     * @return rate The current rate
     */
    function getWrappedTokenBufferRate(address wrappedToken) external view returns (uint256);

    /**
     * @notice Deposit base and wrapped tokens to an internal ERC4626 token buffer.
     * @param wrappedToken The wrapped buffer token
     * @param baseAmountIn The amount of base tokens (e.g., DAI for waDAI)
     * @param wrappedAmountIn The amount of wrapped tokens
     * @return sharesAmountOut The number of "shares" assigned as a result of this deposit.
     */
    function depositToBuffer(
        address wrappedToken,
        uint256 baseAmountIn,
        uint256 wrappedAmountIn
    ) external returns (uint256 sharesAmountOut);

    /**
     * @dev Record a deposit to an ERC4626 buffer.
     * @param baseToken The base token corresponding to the buffer
     * @param wrappedToken The wrapped token, identifying the buffer
     * @param baseAmountIn The amount of base tokens deposited
     * @param wrappedAmountIn The amount of wrapped tokens deposited
     */
    event TokensDepositedToBuffer(
        address indexed baseToken,
        address indexed wrappedToken,
        uint256 baseAmountIn,
        uint256 wrappedAmountIn
    );

    /**
     * @notice Get the number of shares (i.e., virtual BPT) held by a depositor in an ERC4626 buffer.
     * @param wrappedToken The wrapped token identifying the buffer
     * @return sharesAmount The total shares controlled by the caller
     */
    function getBufferShares(address wrappedToken) external view returns (uint256);

    /**
     * @notice Get the total supply for a given buffer.
     * @param wrappedToken The wrapped token identifying the buffer
     * @return totalSupply The current total supply of the buffer (i.e., total shares of virtual BPT)
     */
    function getTotalSupplyOfBuffer(address wrappedToken) external view returns (uint256);

    /**
     * @notice Withdraw shares in an ERC4626 token buffer.
     * @param wrappedToken The wrapped token specifying the buffer
     * @param baseAmountOut The amount of base tokens to withdraw (e.g., DAI for waDAI)
     * @param wrappedAmountOut The amount of wrapped tokens to withdraw
     * @return sharesAmountIn The amount of shares "burned" in exchange for the tokens.
     */
    function withdrawFromBuffer(
        address wrappedToken,
        uint256 baseAmountOut,
        uint256 wrappedAmountOut
    ) external returns (uint256 sharesAmountIn);

    /**
     * @dev Record a withdrawal from an ERC4626 buffer.
     * @param baseToken The base token corresponding to the buffer
     * @param wrappedToken The wrapped token, identifying the buffer
     * @param baseAmountOut The amount of base tokens deposited
     * @param wrappedAmountOut The amount of wrapped tokens deposited
     */
    event TokensWithdrawnFromBuffer(
        address indexed baseToken,
        address indexed wrappedToken,
        uint256 baseAmountOut,
        uint256 wrappedAmountOut
    );

    /**
     * @notice Rebalance an ERC4626 buffer.
     * @param wrappedToken The wrapped token identifying the buffer
     */
    function rebalanceBuffer(address wrappedToken) external;

    /**
     * @notice Initializes a registered pool by adding liquidity; mints BPT tokens for the first time in exchange.
     * @param pool Address of the pool to initialize
     * @param to Address that will receive the output BPT
     * @param tokens Tokens used to seed the pool (must match the registered tokens)
     * @param exactAmountsIn Exact amounts of input tokens
     * @param minBptAmountOut Minimum amount of output pool tokens
     * @param userData Additional (optional) data required for adding initial liquidity
     * @return bptAmountOut Output pool token amount
     */
    function initialize(
        address pool,
        address to,
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

    /**
     * @notice Checks whether a pool is initialized.
     * @dev An initialized pool can be considered registered as well.
     * @param pool Address of the pool to check
     * @return True if the pool is initialized, false otherwise
     */
    function isPoolInitialized(address pool) external view returns (bool);

    /**
     * @notice Gets the tokens registered to a pool.
     * @param pool Address of the pool
     * @return tokens List of tokens in the pool
     */
    function getPoolTokens(address pool) external view returns (IERC20[] memory);

    /**
     * @notice Gets the index of a token in a given pool.
     * @dev Reverts if the pool is not registered, or if the token does not belong to the pool.
     * @param pool Address of the pool
     * @param token Address of the token
     * @return tokenCount Number of tokens in the pool
     * @return index Index corresponding to the given token in the pool's token list
     */
    function getPoolTokenCountAndIndexOfToken(address pool, IERC20 token) external view returns (uint256, uint256);

    /**
     * @notice Gets the raw data for a pool: tokens, raw balances, scaling factors.
     * @return tokens Tokens registered to the pool
     * @return tokenTypes The types of all registered tokens
     * @return balancesRaw Corresponding raw balances of the tokens
     * @return scalingFactors Corresponding scalingFactors of the tokens
     * @return rateProviders Corresponding rateProviders of the tokens (or zero for tokens with no rates)
     */
    function getPoolTokenInfo(
        address pool
    )
        external
        view
        returns (IERC20[] memory, TokenType[] memory, uint256[] memory, uint256[] memory, IRateProvider[] memory);

    /**
     * @notice Retrieve the scaling factors from a pool's rate providers.
     * @dev This is not included in `getPoolTokenInfo` since it makes external calls that might revert,
     * effectively preventing retrieval of basic pool parameters. Tokens without rate providers will always return
     * FixedPoint.ONE (1e18).
     */
    function getPoolTokenRates(address pool) external view returns (uint256[] memory);

    /**
     * @notice Gets the configuration parameters of a pool.
     * @param pool Address of the pool
     * @return Pool configuration
     */
    function getPoolConfig(address pool) external view returns (PoolConfig memory);

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

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    /// @dev Introduce to avoid "stack too deep" - without polluting the Add/RemoveLiquidity params interface.
    struct LiquidityLocals {
        uint256 tokenIndex;
        uint256[] limitsScaled18;
    }

    /**
     * @notice Adds liquidity to a pool.
     * @dev Caution should be exercised when adding liquidity because the Vault has the capability
     * to transfer tokens from any user, given that it holds all allowances.
     *
     * @param params Parameters for the add liquidity (see above for struct definition)
     * @return amountsIn Actual amounts of input tokens
     * @return bptAmountOut Output pool token amount
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function addLiquidity(
        AddLiquidityParams memory params
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    /**
     * @notice Removes liquidity from a pool.
     * @dev Trusted routers can burn pool tokens belonging to any user and require no prior approval from the user.
     * Untrusted routers require prior approval from the user. This is the only function allowed to call
     * _queryModeBalanceIncrease (and only in a query context).
     *
     * @param params Parameters for the remove liquidity (see above for struct definition)
     * @return bptAmountIn Actual amount of BPT burnt
     * @return amountsOut Actual amounts of output tokens
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function removeLiquidity(
        RemoveLiquidityParams memory params
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
     * @return amountCalculatedRaw Calculated swap amount
     * @return amountInRaw Amount of input tokens for the swap
     * @return amountOutRaw Amount of output tokens from the swap
     */
    function swap(
        SwapParams memory params
    ) external returns (uint256 amountCalculatedRaw, uint256 amountInRaw, uint256 amountOutRaw);

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

    /**
     * @notice Returns the Vault Extension address.
     */
    function getVaultExtension() external view returns (address);
}
