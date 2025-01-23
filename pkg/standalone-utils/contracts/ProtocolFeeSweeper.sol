// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeSweeper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeSweeper.sol";
import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

/**
 * @notice Withdraw protocol fees, convert them to a target token, and forward to a recipient.
 * @dev This withdraws all protocol fees previously collected and allocated to the protocol by the
 * `ProtocolFeeController`, processes them with a configurable "burner" (e.g., from CowSwap) and forwards them to
 * a recipient address.
 *
 * An off-chain process can call `collectAggregateFees(pool)` on the fee controller for a given pool, which will
 * collect and allocate the fees to the protocol and pool creator. `getProtocolFeeAmounts(pool)` returns the fee
 * amounts available for withdrawal. If these are great enough, `sweepProtocolFees(pool)` here will withdraw,
 * convert, and forward them to the final recipient. There is also a `sweepProtocolFeesForToken` function to
 * target a single token within a pool.
 */
contract ProtocolFeeSweeper is IProtocolFeeSweeper, SingletonAuthentication, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    /// @notice All pool tokens are ERC20, so this contract should not handle ETH.
    error CannotReceiveEth();

    // Preferred token for receiving protocol fees. Passed to the fee burner as the target of fee token swaps.
    IERC20 private _targetToken;

    // Final destination of the collected protocol fees.
    address private _feeRecipient;

    // Allowlist of valid protocol fee burners.
    mapping(IProtocolFeeBurner => bool) private _protocolFeeBurners;

    // The default configuration on deployment simply forwards all fee tokens to the `feeRecipient`.
    constructor(IVault vault, address feeRecipient) SingletonAuthentication(vault) {
        _setFeeRecipient(feeRecipient);
    }

    /// @inheritdoc IProtocolFeeSweeper
    function sweepProtocolFeesForToken(
        address pool,
        IERC20 feeToken,
        uint256 minAmountOut,
        uint256 deadline,
        IProtocolFeeBurner feeBurner
    ) external nonReentrant authenticate {
        bool feeBurnerProvided = _getValidFeeBurner(feeBurner);

        uint256 existingBalance = feeToken.balanceOf(address(this));

        // Withdraw protocol fees to this contract. Note that governance will need to grant this contract permission
        // to call `withdrawProtocolFeesForToken` on the `ProtocolFeeController.
        getProtocolFeeController().withdrawProtocolFeesForToken(pool, address(this), feeToken);

        uint256 withdrawnBalance = feeToken.balanceOf(address(this)) - existingBalance;

        if (withdrawnBalance > 0) {
            if (feeBurnerProvided) {
                IERC20 targetToken = _targetToken;

                // If the fee token is already the target, there's no need to swap. Simply transfer it.
                if (feeToken == targetToken) {
                    _transferFeeToken(pool, feeToken, withdrawnBalance);
                } else {
                    // Transfer the tokens directly to avoid "hanging approvals," in case the burn is unsuccessful.
                    feeToken.safeTransfer(address(feeBurner), withdrawnBalance);
                    // This is asynchronous; the burner will complete the action and emit an event.
                    feeBurner.burn(
                        pool,
                        feeToken,
                        withdrawnBalance,
                        targetToken,
                        minAmountOut,
                        _feeRecipient,
                        deadline
                    );
                }
            } else {
                // If no burner has been set, fall back on direct transfer of the fee token.
                _transferFeeToken(pool, feeToken, withdrawnBalance);
            }
        }
    }

    function _getValidFeeBurner(IProtocolFeeBurner feeBurner) private view returns (bool feeBurnerProvided) {
        feeBurnerProvided = address(feeBurner) != address(0);

        // Allow passing the zero address (no burner); this will simply transfer the fee tokens directly (e.g., if
        // there is no burner available for a given token).
        if (feeBurnerProvided) {
            if (_protocolFeeBurners[feeBurner]) {
                if (address(_targetToken) == address(0)) {
                    revert InvalidTargetToken();
                }
            } else {
                revert UnsupportedProtocolFeeBurner(address(feeBurner));
            }
        }
    }

    function _transferFeeToken(address pool, IERC20 feeToken, uint256 withdrawnTokenBalance) private {
        address recipient = _feeRecipient;
        feeToken.safeTransfer(recipient, withdrawnTokenBalance);

        emit ProtocolFeeSwept(pool, feeToken, withdrawnTokenBalance, recipient);
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
    function isApprovedProtocolFeeBurner(address protocolFeeBurner) external view returns (bool) {
        return _protocolFeeBurners[IProtocolFeeBurner(protocolFeeBurner)];
    }

    /***************************************************************************
                                Permissioned Functions
    ***************************************************************************/

    /// @inheritdoc IProtocolFeeSweeper
    function setFeeRecipient(address feeRecipient) external authenticate {
        _setFeeRecipient(feeRecipient);
    }

    function _setFeeRecipient(address feeRecipient) internal {
        // Best effort to at least ensure the fee recipient isn't the zero address (so it doesn't literally burn all
        // protocol fees). Governance must ensure this is a valid address, as sweeping is permissionless.
        //
        // We could use a 2-step claim process like the `TimelockAuthorizer` here, but the consequences here are less
        // severe, so that might be overkill. Nothing can be bricked; the worst that can happen is loss of protocol
        // fees until the recipient is updated again.
        if (feeRecipient == address(0)) {
            revert InvalidFeeRecipient();
        }

        _feeRecipient = feeRecipient;

        emit FeeRecipientSet(feeRecipient);
    }

    /// @inheritdoc IProtocolFeeSweeper
    function setTargetToken(IERC20 targetToken) external authenticate {
        _targetToken = targetToken;

        emit TargetTokenSet(targetToken);
    }

    /// @inheritdoc IProtocolFeeSweeper
    function addProtocolFeeBurner(IProtocolFeeBurner protocolFeeBurner) external authenticate {
        if (_protocolFeeBurners[protocolFeeBurner]) {
            revert ProtocolFeeBurnerAlreadyAdded(address(protocolFeeBurner));
        }

        // Since the zero address is a sentinel value indicating no burner should be used, do not allow adding it.
        if (address(protocolFeeBurner) == address(0)) {
            revert InvalidProtocolFeeBurner();
        }

        _protocolFeeBurners[protocolFeeBurner] = true;

        emit ProtocolFeeBurnerAdded(address(protocolFeeBurner));
    }

    /// @inheritdoc IProtocolFeeSweeper
    function removeProtocolFeeBurner(IProtocolFeeBurner protocolFeeBurner) external authenticate {
        if (_protocolFeeBurners[protocolFeeBurner] == false) {
            revert ProtocolFeeBurnerNotAdded(address(protocolFeeBurner));
        }

        _protocolFeeBurners[protocolFeeBurner] = false;

        emit ProtocolFeeBurnerRemoved(address(protocolFeeBurner));
    }

    /// @inheritdoc IProtocolFeeSweeper
    function recoverProtocolFees(IERC20[] memory feeTokens) external nonReentrant {
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
