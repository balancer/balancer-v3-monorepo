// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { StorageSlotExtension } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

/**
 * @notice Abstract base contract for functions shared among all Routers.
 * @dev Common functionality includes access to the sender (which would normally be obscured, since msg.sender in the
 * Vault is the Router contract itself, not the account that invoked the Router), versioning, and the external
 * invocation functions (`permitBatchAndCall` and `multicall`).
 */
abstract contract SenderGuard is ISenderGuard {
    using StorageSlotExtension for *;

    // NOTE: If you use a constant, then it is simply replaced everywhere when this constant is used by what is written
    // after =. If you use immutable, the value is first calculated and then replaced everywhere. That means that if a
    // constant has executable variables, they will be executed every time the constant is used.

    // solhint-disable-next-line var-name-mixedcase
    bytes32 private immutable _SENDER_SLOT = TransientStorageHelpers.calculateSlot(type(SenderGuard).name, "sender");

    // Raw token balances are stored in half a slot, so the max is uint128. Moreover, given that amounts are usually
    // scaled inside the Vault, sending type(uint256).max would result in an overflow and revert.
    uint256 internal constant _MAX_AMOUNT = type(uint128).max;

    /**
     * @notice Saves the user or contract that initiated the current operation.
     * @dev It is possible to nest router calls (e.g., with reentrant hooks), but the sender returned by the Router's
     * `getSender` function will always be the "outermost" caller. Some transactions require the Router to identify
     * multiple senders. Consider the following example:
     *
     * - ContractA has a function that calls the Router, then calls ContractB with the output. ContractB in turn
     * calls back into the Router.
     * - Imagine further that ContractA is a pool with a "before" hook that also calls the Router.
     *
     * When the user calls the function on ContractA, there are three calls to the Router in the same transaction:
     * - 1st call: When ContractA calls the Router directly, to initiate an operation on the pool (say, a swap).
     *             (Sender is contractA, initiator of the operation.)
     *
     * - 2nd call: When the pool operation invokes a hook (say onBeforeSwap), which calls back into the Router.
     *             This is a "nested" call within the original pool operation. The nested call returns, then the
     *             before hook returns, the Router completes the operation, and finally returns back to ContractA
     *             with the result (e.g., a calculated amount of tokens).
     *             (Nested call; sender is still ContractA through all of this.)
     *
     * - 3rd call: When the first operation is complete, ContractA calls ContractB, which in turn calls the Router.
     *             (Not nested, as the original router call from contractA has returned. Sender is now ContractB.)
     */
    modifier saveSender(address sender) {
        bool isExternalSender = _saveSender(sender);
        _;
        _discardSenderIfRequired(isExternalSender);
    }

    function _saveSender(address sender) internal returns (bool isExternalSender) {
        address savedSender = _getSenderSlot().tload();

        // NOTE: Only the most external sender will be saved by the Router.
        if (savedSender == address(0)) {
            _getSenderSlot().tstore(sender);
            isExternalSender = true;
        }
    }

    function _discardSenderIfRequired(bool isExternalSender) internal {
        // Only the external sender shall be cleaned up; if it's not an external sender it means that
        // the value was not saved in this modifier.
        if (isExternalSender) {
            _getSenderSlot().tstore(address(0));
        }
    }

    constructor() {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc ISenderGuard
    function getSender() external view returns (address) {
        return _getSenderSlot().tload();
    }

    function _getSenderSlot() internal view returns (StorageSlotExtension.AddressSlotType) {
        return _SENDER_SLOT.asAddress();
    }
}
