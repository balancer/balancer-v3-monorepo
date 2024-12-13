// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { RevertCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/RevertCodec.sol";

contract CallAndRevert {
    error QuoteResultSpoofed();

    function _callAndRevert(address target, bytes memory data) internal returns (bytes memory) {
        try CallAndRevert(address(this)).callAndRevertHook(target, data) {
            revert("Unexpected success");
        } catch (bytes memory result) {
            return RevertCodec.catchEncodedResult(result);
        }
    }

    function callAndRevertHook(address target, bytes memory data) external returns (uint256) {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = (target).call(data);
        if (success) {
            // This will only revert if result is empty and sender account has no code.
            Address.verifyCallResultFromTarget(msg.sender, success, result);
            // Send result in revert reason.
            revert RevertCodec.Result(result);
        } else {
            // If the call reverted with a spoofed `QuoteResult`, we catch it and bubble up a different reason.
            bytes4 errorSelector = RevertCodec.parseSelector(result);
            if (errorSelector == RevertCodec.Result.selector) {
                revert QuoteResultSpoofed();
            }

            // Otherwise we bubble up the original revert reason.
            RevertCodec.bubbleUpRevert(result);
        }
    }
}
