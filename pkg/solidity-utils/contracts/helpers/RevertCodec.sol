// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

// solhint-disable no-inline-assembly

/// @notice Support `quoteAndRevert`: a v2-style query which always reverts, and returns the result in the return data.
library RevertCodec {
    /**
     * @dev On success of the primary operation in a `quoteAndRevert`, this error is thrown with the return data.
     * @param result The result of the query operation
     */
    error Result(bytes result);

    /// @dev Handle the "reverted without a reason" case (i.e., no return data).
    error ErrorSelectorNotFound();

    function catchEncodedResult(bytes memory resultRaw) internal pure returns (bytes memory) {
        bytes4 errorSelector = RevertCodec.parseSelector(resultRaw);
        if (errorSelector != Result.selector) {
            // Bubble up error message if the revert reason is not the expected one.
            RevertCodec.bubbleUpRevert(resultRaw);
        }

        uint256 resultRawLength = resultRaw.length;
        assembly {
            resultRaw := add(resultRaw, 0x04) // Slice the sighash
            mstore(resultRaw, sub(resultRawLength, 4)) // Set proper length
        }

        return abi.decode(resultRaw, (bytes));
    }

    /// @dev Returns the first 4 bytes in an array, reverting if the length is < 4.
    function parseSelector(bytes memory callResult) internal pure returns (bytes4 errorSelector) {
        if (callResult.length < 4) {
            revert ErrorSelectorNotFound();
        }
        assembly {
            errorSelector := mload(add(callResult, 0x20)) // Load the first 4 bytes from data (skip length offset)
        }
    }

    /// @dev Taken from Openzeppelin's Address.
    function bubbleUpRevert(bytes memory returndata) internal pure {
        // Look for revert reason and bubble it up if present.
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly.
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert ErrorSelectorNotFound();
        }
    }
}
