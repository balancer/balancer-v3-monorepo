// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IComposableCow } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IComposableCow.sol";
import { IProtocolFeeSweeper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeSweeper.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { PackedTokenBalance } from "@balancer-labs/v3-solidity-utils/contracts/helpers/PackedTokenBalance.sol";

import { CowSwapFeeBurner } from "./CowSwapFeeBurner.sol";

/**
 * @title ERC4626CowSwapFeeBurner
 * @notice A contract that burns ERC4626 protocol fee tokens using CowSwap, previously redeeming underlying assets.
 * @dev The Cow Watchtower (https://github.com/cowprotocol/watch-tower) must be running for the burner to function.
 * Only one order per token is allowed at a time.
 */
contract ERC4626CowSwapFeeBurner is CowSwapFeeBurner {
    using SafeERC20 for IERC20;

    /// @notice The amount out is zero.
    error AmountOutIsZero(IERC20 token);

    constructor(
        IProtocolFeeSweeper _protocolFeeSweeper,
        IComposableCow _composableCow,
        address _cowVaultRelayer,
        bytes32 _appData,
        address _initialOwner,
        string memory _version
    ) CowSwapFeeBurner(_protocolFeeSweeper, _composableCow, _cowVaultRelayer, _appData, _initialOwner, _version) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Treats `feeToken` as an ERC4626, redeems `exactFeeTokenAmountIn`, swaps the underlying asset for
     * `targetToken`, and sends the proceeds to the `recipient`.
     * @dev Assumes the sweeper has granted allowance for the fee tokens to the burner prior to the call.
     * @param pool The pool the fees came from (only used for documentation in the event)
     * @param feeToken The token collected from the pool
     * @param exactFeeTokenAmountIn The number of fee tokens collected
     * @param targetToken The desired target token (`tokenOut` of the swap)
     * @param encodedMinAmountsOut The minimum amounts out for the swap, encoded as a 256-bit integer:
     * - Upper 128 bits: the minimum amount of the target token to receive
     * - Lower 128 bits: the minimum amount of the ERC4626 token to receive
     * @param recipient The recipient of the swap proceeds
     * @param deadline Deadline for the burn operation (i.e., swap), after which it will revert
     */
    function burn(
        address pool,
        IERC20 feeToken,
        uint256 exactFeeTokenAmountIn,
        IERC20 targetToken,
        uint256 encodedMinAmountsOut,
        address recipient,
        uint256 deadline
    ) external override onlyProtocolFeeSweeper nonReentrant {
        IERC4626 erc4626Token = IERC4626(address(feeToken));
        IERC20 underlyingToken = IERC20(erc4626Token.asset());

        // In this case we first pull the wrapped token, unwrap, and then proceed to burn by creating an order for
        // the underlying token.
        IERC20(address(erc4626Token)).safeTransferFrom(msg.sender, address(this), exactFeeTokenAmountIn);

        (uint256 minTargetTokenAmountOut, uint256 minERC4626AmountOut) = PackedTokenBalance.fromPackedBalance(
            bytes32(encodedMinAmountsOut)
        );

        uint256 feeTokenBalanceBefore = underlyingToken.balanceOf(address(this));

        erc4626Token.redeem(exactFeeTokenAmountIn, address(this), address(this));

        uint256 feeTokenBalanceAfter = underlyingToken.balanceOf(address(this));
        exactFeeTokenAmountIn = feeTokenBalanceAfter - feeTokenBalanceBefore;

        if (exactFeeTokenAmountIn < minERC4626AmountOut) {
            revert AmountOutBelowMin(underlyingToken, exactFeeTokenAmountIn, minERC4626AmountOut);
        } else if (exactFeeTokenAmountIn == 0) {
            revert AmountOutIsZero(underlyingToken);
        }

        // This case is not handled by the internal `_burn` function, but it's valid: we can consider that the token
        // has already been converted to the correct token, so we just forward the result and finish.
        if (underlyingToken == targetToken) {
            // We apply the slippage check, but not deadline as the order settlement is instant in this case.
            if (exactFeeTokenAmountIn < minTargetTokenAmountOut) {
                revert AmountOutBelowMin(targetToken, exactFeeTokenAmountIn, minTargetTokenAmountOut);
            }

            underlyingToken.safeTransfer(recipient, exactFeeTokenAmountIn);
        } else {
            _burn(
                pool,
                underlyingToken,
                exactFeeTokenAmountIn,
                targetToken,
                minTargetTokenAmountOut,
                recipient,
                deadline,
                false // pullToken
            );
        }
    }
}
