// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
 * This is the basic version that uses only the "fallback" method, simply forwarding all tokens collected to a
 * designated fee recipient (e.g., a multi-sig). It has some infrastructure that will be used for future versions.
 */
contract ProtocolFeeSweeper is SingletonAuthentication {
    using SafeERC20 for IERC20;

    /**
     * @notice Emitted when the target token is updated.
     * @param token The preferred token for receiving protocol fees
     */
    event TargetTokenSet(IERC20 indexed token);

    /**
     * @notice Emitted when a new fee recipient is proposed.
     * @dev Fees will not be distributed until the fee recipient is finalized with `claimFeeRecipient`.
     * @param feeRecipient The intended final destination of collected protocol fees
     */
    event PendingFeeRecipientSet(address indexed feeRecipient);

    /**
     * @notice Emitted when the fee recipient address is verified.
     * @param feeRecipient The final destination of collected protocol fees
     */
    event FeeRecipientSet(address indexed feeRecipient);

    /**
     * @notice Emitted when governance has set the protocol fee burner contract.
     * @param protocolFeeBurner The contract used to "burn" protocol fees (i.e., convert them to the target token)
     */
    event ProtocolFeeBurnerSet(address indexed protocolFeeBurner);

    /// @notice Thrown if we attempt to sweep fees before setting a fee recipient.
    error NoFeeRecipient();

    /// @notice This contract should not receive ETH.
    error CannotReceiveEth();

    modifier withValidFeeRecipient() {
        if (_feeRecipient == address(0)) {
            revert NoFeeRecipient();
        }
        _;
    }

    // Preferred token for receiving protocol fees. This does not need to be validated, since setting it to an
    // invalid or incorrect value would just mean fees could not be converted to it, in which case the contract
    // would fall back on forwarding the tokens as collected.
    IERC20 private _targetToken;

    // Intended destination of the collected protocol fees. Since the protocol fee recipient is of critical importance,
    // it must be claimed by that address to take effect.
    address private _pendingFeeRecipient;

    // Final destination of the collected protocol fees, after confirmation through the claims process.
    address private _feeRecipient;

    // Address of the current "burn" strategy (i.e., swapping fee tokens to the target).
    IProtocolFeeBurner private _protocolFeeBurner;

    constructor(IVault vault, address feeRecipient) SingletonAuthentication(vault) {
        _setPendingFeeRecipient(feeRecipient);
    }

    /**
     * @notice Getter for the pending fee recipient.
     * @dev This will be initialized on deployment, and set to zero once claimed.
     * @return pendingFeeRecipient The proposed fee recipient
     */
    function getPendingFeeRecipient() external view returns(address) {
        return _pendingFeeRecipient;
    }

    /**
     * @notice Getter for the current fee recipient.
     * @dev This will be zero until claimed initially.
     * @return feeRecipient The currently active fee recipient
     */
    function getFeeRecipient() external view returns(address) {
        return _feeRecipient;
    }

    /**
     * @notice Withdraw and distribute protocol fees for a given pool.
     * @dev This will withdraw all fee tokens to this contract, and attempt to distribute them.
     * @param pool The pool from which we're withdrawing fees
     */
    function sweepProtocolFees(address pool) external withValidFeeRecipient() {
        // Collect protocol fees - note that governance will need to grant this contract permission to call
        // `withdrawProtocolFees` on the `ProtocolFeeController. It is not immutable in the Vault, so we need
        // to get it every time.
        IProtocolFeeController feeController = getVault().getProtocolFeeController();
        feeController.withdrawProtocolFees(pool, address(this));

        _processProtocolFees(getVault().getPoolTokens(pool));
    }

    /**
     * @notice Withdraw and distribute protocol fees for a given pool and token.
     * @dev This will withdraw any fees collected on that pool and token, and attempt to distribute them.
     * @param pool The pool from which we're withdrawing fees
     * @param token The fee token
     */
    function sweepProtocolFeesForToken(address pool, IERC20 token) external withValidFeeRecipient() {
        // Collect protocol fees - note that governance will need to grant this contract permission to call
        // `withdrawProtocolFeesForToken` on the `ProtocolFeeController. It is not immutable in the Vault, so we need
        // to get it every time.
        IProtocolFeeController feeController = getVault().getProtocolFeeController();
        feeController.withdrawProtocolFeesForToken(pool, address(this), token);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = token;

        _processProtocolFees(tokens);
    }

    /**
     * @notice Retrieve any tokens "stuck" in this contract (e.g., dust, or failed conversions).
     * @dev It will recover the full balance of all the tokens. This can only be called by the `feeRecipient`.
     * @param tokens The tokens to recover
     */
    function recoverProtocolFees(IERC20[] memory tokens) external {
        if (msg.sender != _feeRecipient) {
            revert SenderNotAllowed();
        }

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 tokenBalance = token.balanceOf(address(this));

            if (tokenBalance > 0) {
                token.safeTransfer(_feeRecipient, tokenBalance);
            }
        }
    }

    /**
     * @notice Start the process of changing the protocol fee recipient.
     * @dev The specified account must call `claimFeeRecipient` to complete the process, proving that the recipient
     * address is a valid account. This is a permissioned function. If this address is set in error and can't be
     * claimed, it can simply be overwritten.
     *
     * @param feeRecipient The address of the new proposed fee recipient
     */
    function setPendingFeeRecipient(address feeRecipient) external authenticate {
        _setPendingFeeRecipient(feeRecipient);
    }

    /**
     * @notice Complete the 2-step process to assign a fee recipient.
     * @dev This must be called by the pending fee recipient.
     */
    function claimFeeRecipient() external {
        if (msg.sender != _pendingFeeRecipient) {
            revert SenderNotAllowed();
        }

        _feeRecipient = _pendingFeeRecipient;
        _pendingFeeRecipient = address(0);

        emit FeeRecipientSet(_feeRecipient);
    }

    /**
     * @notice Set a protocol fee burner, used to convert protocol fees to a target token.
     * @dev This is a permissioned function. If it is not set, the contract will fall back to forwarding the fee tokens
     * directly to the fee recipient.
     *
     * @param protocolFeeBurner The address of the current protocol fee burner
     */
    function setProtocolFeeBurner(IProtocolFeeBurner protocolFeeBurner) external authenticate {
        _protocolFeeBurner = protocolFeeBurner;

        emit ProtocolFeeBurnerSet(address(protocolFeeBurner));
    }

    function _setTargetToken(IERC20 targetToken) internal {
        _targetToken = targetToken;

        emit TargetTokenSet(targetToken);
    }

    function _setPendingFeeRecipient(address feeRecipient) internal {
        _pendingFeeRecipient = feeRecipient;

        emit PendingFeeRecipientSet(feeRecipient);
    }

    // Convert the given tokens to the target token (if enabled), and forward to the fee recipient. This assumes we
    // have externally validated the fee recipient.
    function _processProtocolFees(IERC20[] memory tokens) internal {
        IProtocolFeeBurner burner = _protocolFeeBurner;
        IERC20 targetToken = _targetToken;
        address recipient = _feeRecipient;

        bool canBurn = targetToken != IERC20(address(0)) && burner != IProtocolFeeBurner(address(0));

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 tokenBalance = token.balanceOf(address(this));

            // If this is already the target token (or we haven't set a burner), just forward directly.
            if (canBurn == false || token == targetToken) {
                token.safeTransfer(recipient, tokenBalance);
            } else {
                token.forceApprove(address(burner), tokenBalance);
                _protocolFeeBurner.burn(token, tokenBalance, targetToken, recipient);
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
