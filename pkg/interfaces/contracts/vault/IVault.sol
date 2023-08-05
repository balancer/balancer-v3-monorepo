// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { Asset } from "../solidity-utils/misc/Asset.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Full external interface for the Vault core contract - no external or public methods exist in the contract that
 * don't override one of these declarations.
 */
interface IVault {
    /// Generalities about the Vault:
    ///
    /// The Vault supports standard ERC20 and ERC721 pool tokens. The only deviation from the standards that
    /// is supported is functions that fail to return an expected boolean value: in these scenarios, a non-reverting
    /// call is assumed to be successful.
    ///
    /// - All non-view functions in the Vault are non-reentrant: calling them while another one is mid-execution (e.g.
    /// while execution control is transferred to a token contract during a swap) will result in a revert. View
    /// functions can be called in a re-reentrant way, but doing so might cause them to return inconsistent results.
    /// Contracts calling view functions in the Vault must make sure the Vault has not already been entered.
    ///
    /// - View functions revert if referring to either unregistered Pools, or unregistered tokens for registered Pools.

    /*******************************************************************************
                                    Pool Registration
    *******************************************************************************/

    /**
     * @dev Registers the caller account as a Pool. Must be called by the Pool's contract. Pools and tokens cannot
     * be deregistered.
     *
     * Pools can only interact with tokens they have registered. Users join a Pool by transferring registered tokens,
     * exit by receiving registered tokens, and can only swap registered tokens.
     *
     * Emits a `PoolRegistered` event.
     * @param factory Address of the factory that deployed this pool
     * @param tokens Tokens registered with this pool
     */
    function registerPool(address factory, IERC20[] memory tokens) external;

    /// @dev Returns whether or not an address corresponds to a registered pool.
    function isRegisteredPool(address pool) external view returns (bool);

    /**
     * @dev Returns a Pool's registered tokens and balances.
     *
     * The order of the `tokens` and `balances` arrays is the same order that will be used in `joinPool`, `exitPool`,
     * as well as in all Pool hooks (where applicable).
     */
    function getPoolTokens(address pool) external view returns (IERC20[] memory tokens, uint256[] memory balances);

    /*******************************************************************************
                                 ERC20 Balancer Pool Tokens 
    *******************************************************************************/

    /// @dev Returns the total supply of an ERC20 Token.
    function totalSupplyOfERC20(address poolToken) external view returns (uint256);

    /// @dev Returns an account's balance of an ERC20 Token.
    function balanceOfERC20(address poolToken, address account) external view returns (uint256);

    /**
     * @dev Function to transfer an ERC20 Token.
     */
    function transferERC20(
        address owner,
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Function to transferFrom an ERC20 token.
     */
    function transferFromERC20(
        address spender,
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    /// @dev Returns an owner's ERC20 allowance for a given spender.
    function allowanceOfERC20(
        address poolToken,
        address owner,
        address spender
    ) external view returns (uint256);

    /**
     * @dev function to set a sender's ERC20 allowance for a given spender.
     */
    function approveERC20(
        address sender,
        address spender,
        uint256 amount
    ) external returns (bool);

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    function invoke(bytes calldata data) external payable returns (bytes memory result);

    function settle(IERC20 token) external returns (uint256 paid);

    function send(
        IERC20 token,
        address to,
        uint256 amount
    ) external;

    function mint(
        IERC20 token,
        address to,
        uint256 amount
    ) external;

    function retrieve(
        IERC20 token,
        address from,
        uint256 amount
    ) external;

    function burn(
        IERC20 token,
        address owner,
        uint256 amount
    ) external;

    function getHandler() external view returns (address);

    /// Users can swap tokens with Pools by calling the `swap` and `batchSwap` functions. To do this,
    /// they need not trust Pool contracts in any way: all security checks are made by the Vault. They must however be
    /// aware of the Pools' pricing algorithms in order to estimate the prices Pools will quote.
    ///
    /// The `swap` function executes a single swap, while `batchSwap` can perform multiple swaps in sequence.
    /// In each individual swap, tokens of one kind are sent from the sender to the Pool (this is the 'token in'),
    /// and tokens of another kind are sent from the Pool to the recipient in exchange (this is the 'token out').
    /// More complex swaps, such as one token in to multiple tokens out can be achieved by batching together
    /// individual swaps.
    ///
    /// There are two swap kinds:
    ///  - 'given in' swaps, where the amount of tokens in (sent to the Pool) is known, and the Pool determines (via the
    /// `onSwap` hook) the amount of tokens out (to send to the recipient).
    ///  - 'given out' swaps, where the amount of tokens out (received from the Pool) is known, and the Pool determines
    /// (via the `onSwap` hook) the amount of tokens in (to receive from the sender).
    ///
    /// Additionally, it is possible to chain swaps using a placeholder input amount, which the Vault replaces with
    /// the calculated output of the previous swap. If the previous swap was 'given in', this will be the calculated
    /// tokenOut amount. If the previous swap was 'given out', it will use the calculated tokenIn amount. These extended
    /// swaps are known as 'multihop' swaps, since they 'hop' through a number of intermediate tokens before arriving at
    /// the final intended token.
    ///
    /// In all cases, tokens are only transferred in and out of the Vault (or withdrawn from and deposited into Internal
    /// Balance) after all individual swaps have been completed, and the net token balance change computed. This makes
    /// certain swap patterns, such as multihops, or swaps that interact with the same token pair in multiple Pools,
    /// cost much less gas than they would otherwise.
    ///
    /// It also means that under certain conditions it is possible to perform arbitrage by swapping with multiple
    /// Pools in a way that results in net token movement out of the Vault (profit), with no tokens being sent in (only
    /// updating the Pool's internal accounting).
    ///
    /// To protect users from front-running or the market changing rapidly, they supply a list of 'limits' for each
    /// token involved in the swap, where either the maximum number of tokens to send (by passing a positive value)
    /// or the minimum amount of tokens to receive (by passing a negative value) is specified.
    ///
    /// Additionally, a 'deadline' timestamp can also be provided, forcing the swap to fail if it occurs after
    /// this point in time (e.g. if the transaction failed to be included in a block promptly).
    ///
    /// If interacting with Pools that hold WETH, it is possible to both send and receive ETH directly: the Vault will
    /// do the wrapping and unwrapping. To enable this mechanism, the IAsset sentinel value (the zero address) must be
    /// passed in the `assets` array instead of the WETH address. Note that it is possible to combine ETH and WETH in
    /// the same swap. Any excess ETH will be sent back to the caller (not the sender, which is relevant for relayers).

    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    /**
     * @dev Performs a swap with a single Pool.
     *
     * If the swap is 'given in' (the number of tokens to send to the Pool is known), it returns the amount of tokens
     * taken from the Pool, which must be greater than or equal to `limit`.
     *
     * If the swap is 'given out' (the number of tokens to take from the Pool is known), it returns the amount of tokens
     * sent to the Pool, which must be less than or equal to `limit`.
     *
     * Emits a `Swap` event.
     */
    function swap(SwapParams memory params)
        external
        returns (
            uint256 amountCalculated,
            uint256 amountIn,
            uint256 amountOut
        );

    /**
     * @dev Data for a single swap executed by `swap`. `amount` is either `amountIn` or `amountOut` depending on
     * the `kind` value.
     *
     * `assetIn` and `assetOut` are either token addresses, or the IAsset sentinel value for ETH (the zero address).
     * Note that Pools never interact with ETH directly: it will be wrapped to or unwrapped from WETH by the Vault.
     *
     * The `userData` field is ignored by the Vault, but forwarded to the Pool in the `onSwap` hook, and may be
     * used to extend swap behavior.
     */
    struct SwapParams {
        SwapKind kind;
        address pool;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountGiven;
        uint256 limit;
        uint256 deadline;
        bytes userData;
    }

    /**
     * @dev Emitted for each individual swap performed by `swap` or `batchSwap`.
     */
    event Swap(
        address indexed pool,
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /**
     * @dev Called by users to join a Pool, which transfers tokens from `sender` into the Pool's balance. This will
     * trigger custom Pool behavior, which will typically grant something in return to `recipient` - often tokenized
     * Pool shares.
     *
     * If the caller is not `sender`, it must be an authorized relayer for them.
     *
     * The `assets` and `maxAmountsIn` arrays must have the same length, and each entry indicates the maximum amount
     * to send for each asset. The amounts to send are decided by the Pool and not the Vault: it just enforces
     * these maximums.
     *
     * If joining a Pool that holds WETH, it is possible to send ETH directly: the Vault will do the wrapping. To enable
     * this mechanism, the IAsset sentinel value (the zero address) must be passed in the `assets` array instead of the
     * WETH address. Note that it is not possible to combine ETH and WETH in the same join. Any excess ETH will be sent
     * back to the caller (not the sender, which is important for relayers).
     *
     * `assets` must have the same length and order as the array returned by `getPoolTokens`. This prevents issues when
     * interacting with Pools that register and deregister tokens frequently. If sending ETH however, the array must be
     * sorted *before* replacing the WETH address with the ETH sentinel value (the zero address), which means the final
     * `assets` array might not be sorted. Pools with no registered tokens cannot be joined.
     *
     * If `fromInternalBalance` is true, the caller's Internal Balance will be preferred: ERC20 transfers will only
     * be made for the difference between the requested amount and Internal Balance (if any). Note that ETH cannot be
     * withdrawn from Internal Balance: attempting to do so will trigger a revert.
     *
     * This causes the Vault to call the `IBasePool.onJoinPool` hook on the Pool's contract, where Pools implement
     * their own custom logic. This typically requires additional information from the user (such as the expected number
     * of Pool shares). This can be encoded in the `userData` argument, which is ignored by the Vault and passed
     * directly to the Pool's contract, as is `recipient`.
     *
     * Emits a `PoolBalanceChanged` event.
     */
    function addLiquidity(
        address pool,
        IERC20[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /**
     * @dev Called by users to exit a Pool, which transfers tokens from the Pool's balance to `recipient`. This will
     * trigger custom Pool behavior, which will typically ask for something in return from `sender` - often tokenized
     * Pool shares. The amount of tokens that can be withdrawn is limited by the Pool's `cash` balance (see
     * `getPoolTokenInfo`).
     *
     * If the caller is not `sender`, it must be an authorized relayer for them.
     *
     * The `tokens` and `minAmountsOut` arrays must have the same length, and each entry in these indicates the minimum
     * token amount to receive for each token contract. The amounts to send are decided by the Pool and not the Vault:
     * it just enforces these minimums.
     *
     * If exiting a Pool that holds WETH, it is possible to receive ETH directly: the Vault will do the unwrapping. To
     * enable this mechanism, the IAsset sentinel value (the zero address) must be passed in the `assets` array instead
     * of the WETH address. Note that it is not possible to combine ETH and WETH in the same exit.
     *
     * `assets` must have the same length and order as the array returned by `getPoolTokens`. This prevents issues when
     * interacting with Pools that register and deregister tokens frequently. If receiving ETH however, the array must
     * be sorted *before* replacing the WETH address with the ETH sentinel value (the zero address), which means the
     * final `assets` array might not be sorted. Pools with no registered tokens cannot be exited.
     *
     * If `toInternalBalance` is true, the tokens will be deposited to `recipient`'s Internal Balance. Otherwise,
     * an ERC20 transfer will be performed. Note that ETH cannot be deposited to Internal Balance: attempting to
     * do so will trigger a revert.
     *
     * `minAmountsOut` is the minimum amount of tokens the user expects to get out of the Pool, for each token in the
     * `tokens` array. This array must match the Pool's registered tokens.
     *
     * This causes the Vault to call the `IBasePool.onExitPool` hook on the Pool's contract, where Pools implement
     * their own custom logic. This typically requires additional information from the user (such as the expected number
     * of Pool shares to return). This can be encoded in the `userData` argument, which is ignored by the Vault and
     * passed directly to the Pool's contract.
     *
     * Emits a `PoolBalanceChanged` event.
     */
    function removeLiquidity(
        address pool,
        IERC20[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);

    /**
     * @dev Emitted when a user joins or exits a Pool by calling `joinPool` or `exitPool`, respectively.
     */
    event PoolBalanceChanged(address indexed pool, address indexed liquidityProvider, IERC20[] tokens, int256[] deltas);
}
