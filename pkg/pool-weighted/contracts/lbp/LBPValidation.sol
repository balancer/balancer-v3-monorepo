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

    // Set a boundary on the maximum lock duration, as a safeguard against accidentally locking it forever.
    uint256 internal constant MAX_BPT_LOCK_DURATION = 365 days;

    // Set a boundary on the minimum pool value to migrate; otherwise owners could circumvent the liquidity guarantee
    // by migrating a trivial amount of the proceeds.
    uint256 internal constant MIN_RESERVE_TOKEN_MIGRATION_WEIGHT = 20e16; // 20%

    // Matches WeightedPool constant; ensures the migration can't fail due to an invalid weight value.
    uint256 internal constant MIN_WEIGHTED_POOL_WEIGHT = 1e16; // 1%

    // Start time must be at least this far in the future, to allow time for funding the LBP (which can only be done
    // before the sale starts). It is a uint32 to match the timestamp bit length.
    uint32 internal constant INITIALIZATION_PERIOD = 1 hours;

    /// @notice The owner is the zero address.
    error InvalidOwner();

    /// @notice Cannot create a pool with migration parameters if the migration router is not set.
    error MigrationRouterRequired();

    /// @notice The sum of migrated weights is not equal to 1.
    error InvalidMigrationWeights();

    /// @notice The percentage of BPT to migrate is invalid (must be between 0-100%).
    error InvalidBptPercentageToMigrate();

    /// @notice The BPT lock duration is invalid.
    error InvalidBptLockDuration();

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

    /**
     * @notice Validates migration parameters.
     * @dev This checks that migration parameters are valid if migration is enabled.
     * If all migration parameters are zero, this is considered "no migration" and passes validation.
     * If any parameter is non-zero, all must be valid.
     *
     * Note that it is possible to set bptPercentageToMigrate to a very small (but non-zero) value, undermining the
     * effectiveness of the `MIN_RESERVE_TOKEN_MIGRATION_WEIGHT` check. Nevertheless, we don't wish to impose a
     * minimum here, as migration is an optional feature (i.e., it is zero anyway if migration is turned off). We
     * expect UIs to expose these parameters, and users to review them as part of their due diligence.
     *
     * @param migrationParams The migration parameters to validate
     * @param migrationRouter The migration router address (must be non-zero if migration is enabled)
     * @return hasMigration True if migration parameters indicate migration is enabled
     */
    function validateMigrationParams(
        MigrationParams memory migrationParams,
        address migrationRouter
    ) internal pure returns (bool hasMigration) {
        // If all migration params are zero, this is a no-migration pool
        hasMigration =
            migrationParams.bptPercentageToMigrate != 0 ||
            migrationParams.lockDurationAfterMigration != 0 ||
            migrationParams.migrationWeightProjectToken != 0 ||
            migrationParams.migrationWeightReserveToken != 0;

        if (hasMigration) {
            // If migration is enabled, the migration router must be set
            if (migrationRouter == address(0)) {
                revert MigrationRouterRequired();
            }

            // Validate migration weights sum to 1 and meet minimum requirements
            uint256 totalTokenWeight = migrationParams.migrationWeightProjectToken +
                migrationParams.migrationWeightReserveToken;

            if (
                totalTokenWeight != FixedPoint.ONE ||
                migrationParams.migrationWeightProjectToken < MIN_WEIGHTED_POOL_WEIGHT || // We already know it's > 0
                migrationParams.migrationWeightReserveToken < MIN_RESERVE_TOKEN_MIGRATION_WEIGHT
            ) {
                revert InvalidMigrationWeights();
            }

            // Must be a valid percentage, and doesn't make sense to be zero if there is a migration.
            if (
                migrationParams.bptPercentageToMigrate > FixedPoint.ONE || migrationParams.bptPercentageToMigrate == 0
            ) {
                revert InvalidBptPercentageToMigrate();
            }

            // Cannot go over the maximum duration. There is no minimum duration, but it shouldn't be zero.
            if (
                migrationParams.lockDurationAfterMigration > MAX_BPT_LOCK_DURATION ||
                migrationParams.lockDurationAfterMigration == 0
            ) {
                revert InvalidBptLockDuration();
            }
        }
    }
}
