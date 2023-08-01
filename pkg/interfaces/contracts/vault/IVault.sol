// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { Asset } from "../solidity-utils/misc/Asset.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWETH } from "../solidity-utils/misc/IWETH.sol";

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

    /// @dev Expose the WETH address (for wrapping and unwrapping native ETH).
    // solhint-disable-next-line func-name-mixedcase
    function WETH() external view returns (IWETH);

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

    /// @dev Returns the total supply of an ERC20 Balancer Pool Token.
    function totalSupplyOfERC20(address poolToken) external view returns (uint256);

    /// @dev Returns an account's balance of an ERC20 Balancer Pool Token.
    function balanceOfERC20(address poolToken, address account) external view returns (uint256);

    /**
     * @dev Permissioned function to transfer an ERC20 Balancer Pool Token.
     * Can only be called from a registered pool.
     */
    function transferERC20(address owner, address to, uint256 amount) external returns (bool);

    /**
     * @dev Permissioned function to transferFrom an ERC20 Balancer pool token.
     * Can only be called from a registered pool.
     */
    function transferFromERC20(address spender, address from, address to, uint256 amount) external returns (bool);

    /// @dev Returns an owner's ERC20 BPT allowance for a given spender.
    function allowanceOfERC20(address poolToken, address owner, address spender) external view returns (uint256);

    /**
     * @dev Permissioned function to set a sender's ERC20 BPT allowance for a given spender. Can only be called
     * from a registered pool.
     */
    function approveERC20(address sender, address spender, uint256 amount) external returns (bool);

    /*******************************************************************************
                               ERC721 Balancer Pool Tokens 
    *******************************************************************************/

    /// @dev Returns an account's balance of a Balancer ERC721 pool token.
    function balanceOfERC721(address token, address owner) external view returns (uint256);

    /// @dev Returns the owner of an ERC721 Balancer pool token.
    function ownerOfERC721(address token, uint256 tokenId) external view returns (address);

    /// @dev See {IERC721-getApproved}.
    function getApprovedERC721(address token, uint256 tokenId) external view returns (address);

    /// @dev See {IERC721-isApprovedForAll}.
    function isApprovedForAllERC721(address token, address owner, address operator) external view returns (bool);

    /// @dev Can only be called by a registered ERC721 pool. See {IERC721-approve}.
    function approveERC721(address sender, address to, uint256 tokenId) external;

    /// @dev Can only be called by a registered ERC721 pool. See {IERC721-setApprovalForAll}.
    function setApprovalForAllERC721(address sender, address operator, bool approved) external;

    /// @dev Can only be called by a registered ERC721 pool. See {IERC721-transferFrom}.
    function transferFromERC721(address sender, address from, address to, uint256 tokenId) external;

    /// @dev Can only be called by a registered ERC721 pool. See {IERC721-safeTransferFrom}.
    function safeTransferFromERC721(address sender, address from, address to, uint256 tokenId) external;

    /// @dev Can only be called by a registered ERC721 pool. See {IERC721-safeTransferFrom}.
    function safeTransferFromERC721(
        address sender,
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) external;

    /*******************************************************************************
                                    Add/Remove Liquidity
    *******************************************************************************/

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
        Asset[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /**
     * @dev Emitted when a user joins or exits a Pool by calling `joinPool` or `exitPool`, respectively.
     */
    event PoolBalanceChanged(
        address indexed pool,
        address indexed liquidityProvider,
        IERC20[] tokens,
        int256[] deltas
    );

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
        Asset[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);
}
