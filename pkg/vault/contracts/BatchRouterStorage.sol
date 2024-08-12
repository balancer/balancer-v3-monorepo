// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import {
    TransientEnumerableSet
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/TransientEnumerableSet.sol";

import {
    TransientStorageHelpers,
    AddressMappingSlot
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

/// @notice Transient storage for Batch Router operations.
contract BatchRouterStorage {
    using TransientStorageHelpers for *;

    // solhint-disable var-name-mixedcase

    // NOTE: If you use a constant, then it is simply replaced everywhere when this constant is used
    // by what is written after =. If you use immutable, the value is first calculated and
    // then replaced everywhere. That means that if a constant has executable variables,
    // they will be executed every time the constant is used.
    bytes32 private immutable _CURRENT_SWAP_TOKEN_IN_SLOT = _calculateBatchRouterStorageSlot("currentSwapTokensIn");
    bytes32 private immutable _CURRENT_SWAP_TOKEN_OUT_SLOT = _calculateBatchRouterStorageSlot("currentSwapTokensOut");
    bytes32 private immutable _CURRENT_SWAP_TOKEN_IN_AMOUNTS_SLOT =
        _calculateBatchRouterStorageSlot("currentSwapTokenInAmounts");
    bytes32 private immutable _CURRENT_SWAP_TOKEN_OUT_AMOUNTS_SLOT =
        _calculateBatchRouterStorageSlot("currentSwapTokenOutAmounts");
    bytes32 private immutable _SETTLED_TOKEN_AMOUNTS_SLOT = _calculateBatchRouterStorageSlot("settledTokenAmounts");

    // solhint-enable var-name-mixedcase

    // We use transient storage to track tokens and amounts flowing in and out of a batch swap.
    // Set of input tokens involved in a batch swap.
    function _currentSwapTokensIn() internal view returns (TransientEnumerableSet.AddressSet storage enumerableSet) {
        bytes32 slot = _CURRENT_SWAP_TOKEN_IN_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            enumerableSet.slot := slot
        }
    }

    function _currentSwapTokensOut() internal view returns (TransientEnumerableSet.AddressSet storage enumerableSet) {
        bytes32 slot = _CURRENT_SWAP_TOKEN_OUT_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            enumerableSet.slot := slot
        }
    }

    // token in -> amount: tracks token in amounts within a batch swap.
    function _currentSwapTokenInAmounts() internal view returns (AddressMappingSlot slot) {
        return AddressMappingSlot.wrap(_CURRENT_SWAP_TOKEN_IN_AMOUNTS_SLOT);
    }

    // token out -> amount: tracks token out amounts within a batch swap.
    function _currentSwapTokenOutAmounts() internal view returns (AddressMappingSlot slot) {
        return AddressMappingSlot.wrap(_CURRENT_SWAP_TOKEN_OUT_AMOUNTS_SLOT);
    }

    // token -> amount that is part of the current input / output amounts, but is settled preemptively.
    // This situation happens whenever there is BPT involved in the operation, which is minted and burnt instantly.
    // Since those amounts are not tracked in the inputs / outputs to settle, we need to track them elsewhere
    // to return the correct total amounts in and out for each token involved in the operation.
    function _settledTokenAmounts() internal view returns (AddressMappingSlot slot) {
        return AddressMappingSlot.wrap(_SETTLED_TOKEN_AMOUNTS_SLOT);
    }

    function _calculateBatchRouterStorageSlot(string memory key) internal pure returns (bytes32) {
        return TransientStorageHelpers.calculateSlot(type(BatchRouterStorage).name, key);
    }
}
