// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Library of helper functions related to typecasting arrays.
library CastingHelpers {
    /**
     * @dev Casts an array of uint256 to int256, setting the sign of the result according to the `positive` flag,
     * without checking whether the values fit in the signed 256 bit range.
     */
    function unsafeCastToInt256(
        uint256[] memory values,
        bool positive
    ) internal pure returns (int256[] memory signedValues) {
        signedValues = new int256[](values.length);
        for (uint256 i = 0; i < values.length; ++i) {
            signedValues[i] = positive ? int256(values[i]) : -int256(values[i]);
        }
    }

    /// @dev Returns a native array of addresses as an IERC20[] array. (Used in tests.)
    function asIERC20(address[] memory addresses) internal pure returns (IERC20[] memory tokens) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            tokens := addresses
        }
    }
}
