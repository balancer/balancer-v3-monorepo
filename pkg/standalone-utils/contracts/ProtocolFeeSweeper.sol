// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeSweeper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeSweeper.sol";
import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

/**
 * @notice Withdraw protocol fees, convert them to a target token, and forward to a recipient.
 * @dev This withdraws all protocol fees previously collected and allocated to the protocol by the
 * `ProtocolFeeController`, processes them with a configurable "burner" (e.g., from CowSwap) and forwards them to
 * a recipient contract.
 *
 * An off-chain process can call `collectAggregateFees(pool)` on the fee controller for a given pool, which will
 * collect and allocate the fees to the protocol and pool creator. `getProtocolFeeAmounts(pool)` returns the fee
 * amounts available for withdrawal. If these are great enough, `sweepProtocolFees(pool)` here will withdraw,
 * convert, and forward them to the final recipient. It is also possible to do this for a single token, using
 * `sweepProtocolFeesForToken(pool, token)`.
 *
 * This is the basic version that uses only the "fallback" method, simply forwarding all tokens collected to a
 * designated fee recipient (e.g., a multi-sig). It has some infrastructure that will be used in future versions.
 */
contract ProtocolFeeSweeper is IProtocolFeeSweeper, SingletonAuthentication {
    using SafeERC20 for IERC20;

    /// @notice This contract should not receive ETH.
    error CannotReceiveEth();

    // Preferred token for receiving protocol fees. This does not need to be validated, since setting it to an
    // invalid or incorrect value would just mean fees could not be converted to it, in which case the contract
    // would fall back on forwarding the tokens as collected.
    IERC20 private _targetToken;

    // Final destination of the collected protocol fees, after confirmation through the claims process.
    address private _feeRecipient;

    // Address of the current "burn" strategy (i.e., swapping fee tokens to the target).
    IProtocolFeeBurner private _protocolFeeBurner;

    constructor(IVault vault, address feeRecipient) SingletonAuthentication(vault) {
        _setFeeRecipient(feeRecipient);
    }

    /// @inheritdoc IProtocolFeeSweeper
    function sweepProtocolFees(address pool) external {
        // Collect protocol fees - note that governance will need to grant this contract permission to call
        // `withdrawProtocolFees` on the `ProtocolFeeController.
        getProtocolFeeController().withdrawProtocolFees(pool, address(this));

        _processProtocolFees(pool, getVault().getPoolTokens(pool));
    }

    // Convert the given tokens to the target token (if enabled), and forward to the fee recipient. This assumes we
    // have externally validated the fee recipient.
    function _processProtocolFees(address pool, IERC20[] memory tokens) internal {
        IProtocolFeeBurner burner = _protocolFeeBurner;
        IERC20 targetToken = _targetToken;
        address recipient = _feeRecipient;

        bool canBurn = targetToken != IERC20(address(0)) && burner != IProtocolFeeBurner(address(0));

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 feeToken = tokens[i];
            uint256 tokenBalance = feeToken.balanceOf(address(this));

            // If no balance, nothing to do.
            if (tokenBalance == 0) {
                continue;
            }

            // If this is already the target token (or we haven't set a burner), just forward directly.
            if (canBurn && feeToken != targetToken) {
                feeToken.forceApprove(address(burner), tokenBalance);
                // This is asynchronous; the burner will complete the action and emit an event.
                _protocolFeeBurner.burn(pool, feeToken, tokenBalance, targetToken, recipient);
            } else {
                feeToken.safeTransfer(recipient, tokenBalance);

                emit ProtocolFeeSwept(pool, feeToken, tokenBalance, recipient);
            }
        }
    }

    /// @inheritdoc IProtocolFeeSweeper
    function getProtocolFeeController() public view returns (IProtocolFeeController) {
        return getVault().getProtocolFeeController();
    }

    /// @inheritdoc IProtocolFeeSweeper
    function getTargetToken() external view returns (IERC20) {
        return _targetToken;
    }

    /// @inheritdoc IProtocolFeeSweeper
    function getFeeRecipient() external view returns (address) {
        return _feeRecipient;
    }

    /// @inheritdoc IProtocolFeeSweeper
    function getProtocolFeeBurner() external view returns (IProtocolFeeBurner) {
        return _protocolFeeBurner;
    }

    /***************************************************************************
                                Permissioned Functions
    ***************************************************************************/

    /// @inheritdoc IProtocolFeeSweeper
    function setFeeRecipient(address feeRecipient) external authenticate {
        _setFeeRecipient(feeRecipient);
    }

    function _setFeeRecipient(address feeRecipient) internal {
        _feeRecipient = feeRecipient;

        emit FeeRecipientSet(feeRecipient);
    }

    /// @inheritdoc IProtocolFeeSweeper
    function setProtocolFeeBurner(IProtocolFeeBurner protocolFeeBurner) external authenticate {
        _setProtocolFeeBurner(protocolFeeBurner);
    }

    function _setProtocolFeeBurner(IProtocolFeeBurner protocolFeeBurner) internal {
        _protocolFeeBurner = protocolFeeBurner;

        emit ProtocolFeeBurnerSet(address(protocolFeeBurner));
    }

    /// @inheritdoc IProtocolFeeSweeper
    function setTargetToken(IERC20 targetToken) external authenticate {
        _setTargetToken(targetToken);
    }

    function _setTargetToken(IERC20 targetToken) internal {
        _targetToken = targetToken;

        emit TargetTokenSet(targetToken);
    }

    /// @inheritdoc IProtocolFeeSweeper
    function recoverProtocolFees(IERC20[] memory feeTokens) external {
        if (msg.sender != _feeRecipient) {
            revert SenderNotAllowed();
        }

        for (uint256 i = 0; i < feeTokens.length; ++i) {
            IERC20 feeToken = feeTokens[i];
            uint256 tokenBalance = feeToken.balanceOf(address(this));

            if (tokenBalance > 0) {
                feeToken.safeTransfer(msg.sender, tokenBalance);
            }
        }
    }

    /*******************************************************************************
                                     Default handlers
    *******************************************************************************/

    // Maybe these aren't needed, but given the general sensitivity of this contract, preemptively disallow any
    // ETH-related shenanigans. Tokens are always ERC20, so there should be no ETH involved in any operations.

    receive() external payable {
        revert CannotReceiveEth();
    }

    // solhint-disable no-complex-fallback

    fallback() external payable {
        if (msg.value > 0) {
            revert CannotReceiveEth();
        }

        revert("Not implemented");
    }
}
