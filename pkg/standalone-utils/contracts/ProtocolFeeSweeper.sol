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

    // Address of the current "burner" contract (i.e., swapping fee tokens to the target).
    IProtocolFeeBurner private _protocolFeeBurner;

    // The default configuration on deployment simply forwards all fee tokens to the `feeRecipient`.
    constructor(IVault vault, address feeRecipient) SingletonAuthentication(vault) {
        _setFeeRecipient(feeRecipient);
    }

    /// @inheritdoc IProtocolFeeSweeper
    function sweepProtocolFeesForToken(address pool, IERC20 feeToken) external nonReentrant authenticate {
        IProtocolFeeBurner feeBurner = _getValidBurner();

        uint256 withdrawnBalance = _withdrawProtocolFeesForToken(pool, feeToken);

        _sweepFeeToken(pool, feeToken, withdrawnBalance, feeBurner);
    }

    function _withdrawProtocolFeesForToken(address pool, IERC20 feeToken) internal returns (uint256 withdrawnBalance) {
        // There could be tokens "left over" from uncompleted burns from previous sweeps. Only process the "new"
        // fees collected from the current withdrawal.
        uint256 existingBalance = feeToken.balanceOf(address(this));

        // Withdraw protocol fees to this contract. Note that governance will need to grant this contract permission
        // to call `withdrawProtocolFeesForToken` on the `ProtocolFeeController.
        getProtocolFeeController().withdrawProtocolFeesForToken(pool, address(this), feeToken);

        withdrawnBalance = feeToken.balanceOf(address(this)) - existingBalance;
    }

    /// @inheritdoc IProtocolFeeSweeper
    function sweepProtocolFees(address pool) external nonReentrant authenticate {
        IProtocolFeeBurner feeBurner = _getValidBurner();

        (IERC20[] memory poolTokens, uint256[] memory withdrawnBalances) = _withdrawProtocolFees(pool);

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            _sweepFeeToken(pool, poolTokens[i], withdrawnBalances[i], feeBurner);
        }
    }

    function _withdrawProtocolFees(
        address pool
    ) internal returns (IERC20[] memory poolTokens, uint256[] memory withdrawnBalances) {
        poolTokens = getVault().getPoolTokens(pool);
        uint256 numTokens = poolTokens.length;

        // There could be tokens "left over" from uncompleted burns from previous sweeps. Only process the "new"
        // fees collected from the current withdrawal.
        uint256[] memory existingBalances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            existingBalances[i] = poolTokens[i].balanceOf(address(this));
        }

        // Withdraw protocol fees to this contract. Note that governance will need to grant this contract permission
        // to call `withdrawProtocolFees` on the `ProtocolFeeController.
        getProtocolFeeController().withdrawProtocolFees(pool, address(this));

        withdrawnBalances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            withdrawnBalances[i] = poolTokens[i].balanceOf(address(this)) - existingBalances[i];
        }
    }

    // Convert the given token to the target token (if the fee burner is enabled), and forward to the fee recipient.
    function _sweepFeeToken(
        address pool,
        IERC20 feeToken,
        uint256 withdrawnTokenBalance,
        IProtocolFeeBurner feeBurner
    ) internal {
        // Short-circuit if nothing to do.
        if (withdrawnTokenBalance == 0) {
            return;
        }

        // If no burner has been set, fall back on direct transfer of the fee token.
        if (address(feeBurner) == address(0)) {
            _transferFeeToken(pool, feeToken, withdrawnTokenBalance);
        } else {
            IERC20 targetToken = _targetToken;

            // If the fee token is already the target, there's no need to swap. Simply transfer it.
            if (feeToken == targetToken) {
                _transferFeeToken(pool, feeToken, withdrawnTokenBalance);
            } else {
                // Transfer the tokens directly to avoid "hanging approvals," in case the burn is unsuccessful.
                feeToken.safeTransfer(address(feeBurner), withdrawnTokenBalance);
                // This is asynchronous; the burner will complete the action and emit an event.
                feeBurner.burn(pool, feeToken, withdrawnTokenBalance, targetToken, _feeRecipient);
            }
        }
    }

    function _transferFeeToken(address pool, IERC20 feeToken, uint256 withdrawnTokenBalance) private {
        address recipient = _feeRecipient;
        feeToken.safeTransfer(recipient, withdrawnTokenBalance);

        emit ProtocolFeeSwept(pool, feeToken, withdrawnTokenBalance, recipient);
    }

    function _getValidBurner() private view returns (IProtocolFeeBurner feeBurner) {
        feeBurner = _protocolFeeBurner;

        if (address(feeBurner) != address(0)) {
            if (address(_targetToken) == address(0)) {
                revert InvalidTargetToken();
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
    function setProtocolFeeBurner(IProtocolFeeBurner protocolFeeBurner) external authenticate {
        _protocolFeeBurner = protocolFeeBurner;

        emit ProtocolFeeBurnerSet(address(protocolFeeBurner));
    }

    /// @inheritdoc IProtocolFeeSweeper
    function setTargetToken(IERC20 targetToken) external authenticate {
        _targetToken = targetToken;

        emit TargetTokenSet(targetToken);
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
