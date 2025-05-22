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

import { CowSwapFeeBurner } from "./CowSwapFeeBurner.sol";

/**
 * @title ERC4626CowSwapFeeBurner
 * @notice A contract that burns ERC4626 protocol fee tokens using CowSwap, previously redeeming underlying assets.
 * @dev The Cow Watchtower (https://github.com/cowprotocol/watch-tower) must be running for the burner to function.
 * Only one order per token is allowed at a time.
 */
contract ERC4626CowSwapFeeBurner is CowSwapFeeBurner {
    using SafeERC20 for IERC20;

    constructor(
        IProtocolFeeSweeper _protocolFeeSweeper,
        IComposableCow _composableCow,
        address _vaultRelayer,
        bytes32 _appData,
        string memory _version
    ) CowSwapFeeBurner(_protocolFeeSweeper, _composableCow, _vaultRelayer, _appData, _version) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Treats `feeToken` as an ERC4626, redeems `exactFeeTokenAmountIn`, swaps the underlying asset for
     * `targetToken`, and sends the proceeds to the `recipient`.
     * @dev Assumes the sweeper has granted allowance for the fee tokens to the burner prior to the call.
     * @param feeToken The token collected from the pool
     * @param exactFeeTokenAmountIn The number of fee tokens collected
     * @param targetToken The desired target token (`tokenOut` of the swap)
     * @param minTargetTokenAmountOut The minimum `amountOut` for the swap
     * @param recipient The recipient of the swap proceeds
     * @param deadline Deadline for the burn operation (i.e., swap), after which it will revert
     */
    function burn(
        IERC20 feeToken,
        uint256 exactFeeTokenAmountIn,
        IERC20 targetToken,
        uint256 minTargetTokenAmountOut,
        address recipient,
        uint256 deadline
    ) external override onlyProtocolFeeSweeper nonReentrant {
        // In this case we first pull the wrapped token, unwrap, and then proceed to burn by creating an order for
        // the underlying token.
        feeToken.safeTransferFrom(msg.sender, address(this), exactFeeTokenAmountIn);

        // Redeem and overwrite inputs with new asset and unwrapped amount.
        IERC4626 erc4626Token = IERC4626(address(feeToken));
        feeToken = IERC20(erc4626Token.asset());
        exactFeeTokenAmountIn = erc4626Token.redeem(exactFeeTokenAmountIn, address(this), address(this));

        // This case is not handled by the internal `_burn` function, but it's valid: we can consider that the token
        // has already been converted to the correct token, so we just forward the result and finish.
        if (feeToken == targetToken) {
            // We apply the slippage check, but not deadline as the order settlement is instant in this case.
            if (exactFeeTokenAmountIn < minTargetTokenAmountOut) {
                revert AmountOutBelowMin(targetToken, exactFeeTokenAmountIn, minTargetTokenAmountOut);
            }

            feeToken.safeTransfer(recipient, exactFeeTokenAmountIn);
        } else {
            _burn(
                feeToken,
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
