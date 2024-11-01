// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
     *
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @param amountUnderlying Amount of underlying tokens that will be deposited into the buffer
     * @param amountWrapped Amount of wrapped tokens that will be deposited into the buffer
     * @param minIssuedShares Minimum amount of shares to receive from the buffer, expressed in underlying token
     * native decimals
     * @return issuedShares the amount of tokens sharesOwner has in the buffer, denominated in underlying tokens
     * (This is the BPT of the Vault's internal ERC4626 buffer.)
     */
    function initializeBuffer(
        IERC4626 wrappedToken,
        uint256 amountUnderlying,
        uint256 amountWrapped,
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
     * @param exactSharesToIssue The value in underlying tokens that `sharesOwner` wants to add to the buffer,
     * in underlying token decimals
     * @return amountUnderlying Amount of underlying tokens deposited into the buffer
     * @return amountWrapped Amount of wrapped tokens deposited into the buffer
     */
    function addLiquidityToBuffer(
        IERC4626 wrappedToken,
        uint256 maxAmountUnderlyingIn,
        uint256 maxAmountWrappedIn,
        uint256 exactSharesToIssue
    ) external returns (uint256 amountUnderlying, uint256 amountWrapped);

    function removeLiquidityFromBuffer(
        IERC4626 wrappedToken,
        uint256 sharesToRemove,
        uint256 minAmountUnderlyingOut,
        uint256 minAmountWrappedOut
    ) external returns (uint256 removedUnderlyingBalance, uint256 removedWrappedBalance);
}
