// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { AddLiquidityKind, RemoveLiquidityKind, SwapKind } from "./VaultTypes.sol";

/// @notice User-friendly interface for Buffer liquidity operations with the Vault.
interface IBufferRouter {
    /*******************************************************************************
                                  ERC4626 Buffers
    *******************************************************************************/

    /**
     * @notice Adds liquidity for the first time to an internal ERC4626 buffer in the Vault.
     * @dev Calling this method binds the wrapped token to its underlying asset internally; the asset in the wrapper
     * cannot change afterwards, or every other operation on that wrapper (add / remove / wrap / unwrap) will fail.
     * To avoid unexpected behavior, always initialize buffers before creating or initializing any pools that contain
     * the wrapped tokens to be used with them.
     *
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @param exactAmountUnderlyingIn Amount of underlying tokens that will be deposited into the buffer
     * @param exactAmountWrappedIn Amount of wrapped tokens that will be deposited into the buffer
     * @param minIssuedShares Minimum amount of shares to receive from the buffer, expressed in underlying token
     * native decimals
     * @return issuedShares the amount of tokens sharesOwner has in the buffer, denominated in underlying tokens
     * (This is the BPT of the Vault's internal ERC4626 buffer.)
     */
    function initializeBuffer(
        IERC4626 wrappedToken,
        uint256 exactAmountUnderlyingIn,
        uint256 exactAmountWrappedIn,
        uint256 minIssuedShares
    ) external returns (uint256 issuedShares);

    /**
     * @notice Adds liquidity proportionally to an internal ERC4626 buffer in the Vault.
     * @dev Requires the buffer to be initialized beforehand. Restricting adds to proportional simplifies the Vault
     * code, avoiding rounding issues and minimum amount checks. It is possible to add unbalanced by interacting
     * with the wrapper contract directly.
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @param maxAmountUnderlyingIn Maximum amount of underlying tokens to add to the buffer. It is expressed in
     * underlying token native decimals
     * @param maxAmountWrappedIn Maximum amount of wrapped tokens to add to the buffer. It is expressed in wrapped
     * token native decimals
     * @param exactSharesToIssue The amount of shares that `sharesOwner` wants to add to the buffer, in underlying
     * token decimals
     * @return amountUnderlyingIn Amount of underlying tokens deposited into the buffer
     * @return amountWrappedIn Amount of wrapped tokens deposited into the buffer
     */
    function addLiquidityToBuffer(
        IERC4626 wrappedToken,
        uint256 maxAmountUnderlyingIn,
        uint256 maxAmountWrappedIn,
        uint256 exactSharesToIssue
    ) external returns (uint256 amountUnderlyingIn, uint256 amountWrappedIn);

    /**
     * @notice Queries an `initializeBuffer` operation without actually executing it.
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @param exactAmountUnderlyingIn Amount of underlying tokens that the sender wishes to deposit into the buffer
     * @param exactAmountWrappedIn Amount of wrapped tokens that the sender wishes to deposit into the buffer
     * @return issuedShares The amount of shares that would be minted, in underlying token decimals
     */
    function queryInitializeBuffer(
        IERC4626 wrappedToken,
        uint256 exactAmountUnderlyingIn,
        uint256 exactAmountWrappedIn
    ) external returns (uint256 issuedShares);

    /**
     * @notice Queries an `addLiquidityToBuffer` operation without actually executing it.
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @param exactSharesToIssue The amount of shares that would be minted, in underlying token decimals
     * @return amountUnderlyingIn Amount of underlying tokens that would be deposited into the buffer
     * @return amountWrappedIn Amount of wrapped tokens that would be deposited into the buffer
     */
    function queryAddLiquidityToBuffer(
        IERC4626 wrappedToken,
        uint256 exactSharesToIssue
    ) external returns (uint256 amountUnderlyingIn, uint256 amountWrappedIn);

    /**
     * @notice Queries an `removeLiquidityFromBuffer` operation without actually executing it.
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @param exactSharesToRemove The amount of shares that would be burned, in underlying token decimals
     * @return removedUnderlyingBalanceOut Amount of underlying tokens that would be removed from the buffer
     * @return removedWrappedBalanceOut Amount of wrapped tokens that would be removed from the buffer
     */
    function queryRemoveLiquidityFromBuffer(
        IERC4626 wrappedToken,
        uint256 exactSharesToRemove
    ) external returns (uint256 removedUnderlyingBalanceOut, uint256 removedWrappedBalanceOut);
}
