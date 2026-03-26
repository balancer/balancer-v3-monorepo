// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { GradualValueChange } from "../lib/GradualValueChange.sol";

/**
 * @notice Shared validation library for LBP parameters.
 * @dev This library is used by both factories (for clear error messages) and pools (for direct deployment protection).
 */
library LBPValidation {
    // solhint-disable private-vars-leading-underscore

    // Start time must be at least this far in the future, to allow time for funding the LBP (which can only be done
    // before the sale starts). It is a uint32 to match the timestamp bit length.
    uint32 internal constant INITIALIZATION_PERIOD = 1 hours;

    /// @notice The owner is the zero address.
    error InvalidOwner();

    /// @notice The project and reserve tokens must be different.
    error TokensMustBeDifferent();

    /// @notice The project token is the zero address.
    error InvalidProjectToken();

    /// @notice The reserve token is the zero address.
    error InvalidReserveToken();

    /**
     * @notice Validates common LBP parameters.
     * @dev This should be called by both factories for early validation, and pools for direct deployment protection.
     * Note that the time is also validated here, and unlike previous versions LBPs, the startTime must be in the
     * future, due to constraints around funding and initialization.
     *
     * @param lbpCommonParams The common LBP parameters to validate
     */
    function validateCommonParams(LBPCommonParams memory lbpCommonParams) internal view {
        // In practice, this is already checked by Ownable.
        if (lbpCommonParams.owner == address(0)) {
            revert InvalidOwner();
        }

        if (lbpCommonParams.projectToken == IERC20(address(0))) {
            revert InvalidProjectToken();
        }

        if (lbpCommonParams.reserveToken == IERC20(address(0))) {
            revert InvalidReserveToken();
        }

        if (lbpCommonParams.projectToken == lbpCommonParams.reserveToken) {
            revert TokensMustBeDifferent();
        }

        if (
            lbpCommonParams.startTime > lbpCommonParams.endTime ||
            // solhint-disable-next-line not-rely-on-time
            lbpCommonParams.startTime < block.timestamp + INITIALIZATION_PERIOD
        ) {
            revert GradualValueChange.InvalidStartTime(lbpCommonParams.startTime, lbpCommonParams.endTime);
        }
    }
}
