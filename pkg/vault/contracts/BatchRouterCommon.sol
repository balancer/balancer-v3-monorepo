// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import {
    TransientEnumerableSet
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/TransientEnumerableSet.sol";
import {
    TransientStorageHelpers,
    AddressToUintMappingSlot
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

import { RouterCommon } from "./RouterCommon.sol";

/// @notice Transient storage for Batch and Composite Liquidity Router operations.
contract BatchRouterCommon is RouterCommon {
    using TransientEnumerableSet for TransientEnumerableSet.AddressSet;
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
    // solhint-disable no-inline-assembly

    constructor(IVault vault, IWETH weth, IPermit2 permit2) RouterCommon(vault, weth, permit2) {
        // solhint-disable-previous-line no-empty-blocks
    }

    // We use transient storage to track tokens and amounts flowing in and out of a batch swap.
    // Set of input tokens involved in a batch swap.
    function _currentSwapTokensIn() internal view returns (TransientEnumerableSet.AddressSet storage enumerableSet) {
        bytes32 slot = _CURRENT_SWAP_TOKEN_IN_SLOT;
        assembly ("memory-safe") {
            enumerableSet.slot := slot
        }
    }

    function _currentSwapTokensOut() internal view returns (TransientEnumerableSet.AddressSet storage enumerableSet) {
        bytes32 slot = _CURRENT_SWAP_TOKEN_OUT_SLOT;
        assembly ("memory-safe") {
            enumerableSet.slot := slot
        }
    }

    // token in -> amount: tracks token in amounts within a batch swap.
    function _currentSwapTokenInAmounts() internal view returns (AddressToUintMappingSlot slot) {
        return AddressToUintMappingSlot.wrap(_CURRENT_SWAP_TOKEN_IN_AMOUNTS_SLOT);
    }

    // token out -> amount: tracks token out amounts within a batch swap.
    function _currentSwapTokenOutAmounts() internal view returns (AddressToUintMappingSlot slot) {
        return AddressToUintMappingSlot.wrap(_CURRENT_SWAP_TOKEN_OUT_AMOUNTS_SLOT);
    }

    // token -> amount that is part of the current input / output amounts, but is settled preemptively.
    // This situation happens whenever there is BPT involved in the operation, which is minted and burned instantly.
    // Since those amounts are not tracked in the inputs / outputs to settle, we need to track them elsewhere
    // to return the correct total amounts in and out for each token involved in the operation.
    function _settledTokenAmounts() internal view returns (AddressToUintMappingSlot slot) {
        return AddressToUintMappingSlot.wrap(_SETTLED_TOKEN_AMOUNTS_SLOT);
    }

    function _calculateBatchRouterStorageSlot(string memory key) internal pure returns (bytes32) {
        return TransientStorageHelpers.calculateSlot(type(BatchRouterCommon).name, key);
    }

    /*******************************************************************************
                                    Settlement
    *******************************************************************************/

    /// @notice Settles batch and composite liquidity operations, after credits and debits are computed.
    function _settlePaths(address sender, bool wethIsEth) internal {
        // numTokensIn / Out may be 0 if the inputs and / or outputs are not transient.
        // For example, a swap starting with a 'remove liquidity' step will already have burned the input tokens,
        // in which case there is nothing to settle. Then, since we're iterating backwards below, we need to be able
        // to subtract 1 from these quantities without reverting, which is why we use signed integers.
        int256 numTokensIn = int256(_currentSwapTokensIn().length());
        int256 numTokensOut = int256(_currentSwapTokensOut().length());

        // Iterate backwards, from the last element to 0 (included).
        // Removing the last element from a set is cheaper than removing the first one.
        for (int256 i = int256(numTokensIn - 1); i >= 0; --i) {
            address tokenIn = _currentSwapTokensIn().unchecked_at(uint256(i));
            _takeTokenIn(sender, IERC20(tokenIn), _currentSwapTokenInAmounts().tGet(tokenIn), wethIsEth);
            // Erases delta, in case more than one batch router operation is called in the same transaction.
            _currentSwapTokenInAmounts().tSet(tokenIn, 0);
            _currentSwapTokensIn().remove(tokenIn);
        }

        for (int256 i = int256(numTokensOut - 1); i >= 0; --i) {
            address tokenOut = _currentSwapTokensOut().unchecked_at(uint256(i));
            _sendTokenOut(sender, IERC20(tokenOut), _currentSwapTokenOutAmounts().tGet(tokenOut), wethIsEth);
            // Erases delta, in case more than one batch router operation is called in the same transaction.
            _currentSwapTokenOutAmounts().tSet(tokenOut, 0);
            _currentSwapTokensOut().remove(tokenOut);
        }

        // Return the rest of ETH to sender.
        _returnEth(sender);
    }
}
