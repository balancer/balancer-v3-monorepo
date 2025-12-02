// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import { MigrationParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { LBPValidation } from "./LBPValidation.sol";

/**
 * @notice Base contract for LBP factories.
 * @dev This is a factory for LBPools, allowing only two tokens and restricting the LBP to a single token sale, with
 * common parameters specified on deployment. Derived LBP factories may have additional type-specific features.
 */
abstract contract BaseLBPFactory is IPoolVersion, ReentrancyGuardTransient, Version {
    // LBPs are constrained to two tokens: project (the token being sold), and reserve (e.g., USDC or WETH).
    uint256 internal constant _TWO_TOKENS = 2;

    // The pool version and router addresses are stored in the factory and passed down to the pools on deployment.
    string internal _poolVersion;

    address internal immutable _trustedRouter;
    address internal immutable _migrationRouter;

    /**
     * @notice Emitted on deployment so that offchain processes know which token is which from the beginning.
     * @dev This information is also available onchain through immutable data and explicit getters on the pool.
     * @param pool The address of the new pool
     * @param projectToken The address of the project token (being distributed in the sale)
     * @param reserveToken The address of the reserve token (used to purchase the project token)
     */
    event LBPoolCreated(address indexed pool, IERC20 indexed projectToken, IERC20 indexed reserveToken);

    /**
     * @notice Emitted when the migration parameters are set for a pool.
     * @dev This event is emitted when a pool is created with migration parameters.
     * @param pool Liquidity Bootstrapping Pool
     * @param lockDurationAfterMigration The duration for which the BPT will be locked after migration
     * @param bptPercentageToMigrate The percentage of the BPT to migrate from the LBP to the new weighted pool
     * @param migrationWeightProjectToken The weight of the project token
     * @param migrationWeightReserveToken The weight of the reserve token
     */
    event MigrationParamsSet(
        address indexed pool,
        uint256 lockDurationAfterMigration,
        uint256 bptPercentageToMigrate,
        uint256 migrationWeightProjectToken,
        uint256 migrationWeightReserveToken
    );

    /// @notice The zero address was given for the trusted router.
    error InvalidTrustedRouter();

    constructor(
        string memory factoryVersion,
        string memory poolVersion,
        address trustedRouter,
        address migrationRouter
    ) Version(factoryVersion) {
        if (trustedRouter == address(0)) {
            revert InvalidTrustedRouter();
        }

        // LBPools are deployed with a router known to reliably report the originating address on operations.
        // This is used to ensure that only the owner can add liquidity to an LBP.
        _trustedRouter = trustedRouter;

        // In order to support migration, the factory must have a valid migration router, which withdraws, deploys a
        // successor weighted pool, and locks up the BPT for the specified duration. Migration is optional per LBP,
        // but all pools that choose migration must use the same router, set at the factory level. If this is zero,
        // migration is unsupported for the pool type.
        _migrationRouter = migrationRouter;

        _poolVersion = poolVersion;
    }

    /**
     * @notice Returns the maximum duration the BPT can be locked after migration.
     * @dev The BPT timelock prevents withdrawal of proceeds after the sale and migration, representing a Best effort
     * attempt to ensure that the LBP owner leaves liquidity on the protocol after the sale. This maximum protects
     * the liquidity from being locked forever (e.g., if the pool is misconfigured).
     *
     * @return maxBptLockDuration The maximum amount of time the BPT can be locked, preventing withdrawal by the owner
     */
    function getMaxBptLockDuration() external pure returns (uint256) {
        return LBPValidation.MAX_BPT_LOCK_DURATION;
    }

    /**
     * @notice Returns the minimum weight of the reserve token in the successor weighted pool after migration.
     * @return The minimum weight of the reserve token in the post-migration weighted pool
     */
    function getMinReserveTokenMigrationWeight() external pure returns (uint256) {
        return LBPValidation.MIN_RESERVE_TOKEN_MIGRATION_WEIGHT;
    }

    /// @inheritdoc IPoolVersion
    function getPoolVersion() external view returns (string memory) {
        return _poolVersion;
    }

    /**
     * @notice Returns trusted router, which is the gateway to add liquidity to the pool.
     * @return trustedRouter The address of the trusted router, guaranteed to reliably report the sender
     */
    function getTrustedRouter() external view returns (address) {
        return _trustedRouter;
    }

    /**
     * @notice Returns the migration router, which is used to migrate liquidity from an LBP to a new weighted pool.
     * @return migrationRouter The custom router with permission to withdraw liquidity and lock BPT
     */
    function getMigrationRouter() external view returns (address) {
        return _migrationRouter;
    }

    // Helper function to create a `TokenConfig` array from the two LBP tokens.
    function _buildTokenConfig(
        IERC20 projectToken,
        IERC20 reserveToken
    ) internal pure returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](_TWO_TOKENS);

        (tokenConfig[0].token, tokenConfig[1].token) = projectToken < reserveToken
            ? (projectToken, reserveToken)
            : (reserveToken, projectToken);
    }

    /**
     * @notice Emits common pool creation events in a consistent order.
     * @dev This helper ensures all LBP factories emit events consistently:
     * 1. LBPoolCreated (with pool address and tokens)
     * 2. MigrationParamsSet (if migration is enabled)
     *
     * Derived factories should emit their type-specific event before calling this.
     *
     * @param pool The address of the newly created pool
     * @param projectToken The project token address
     * @param reserveToken The reserve token address
     * @param migrationParams The migration parameters (may be empty)
     * @param hasMigration Whether migration is enabled for this pool
     */
    function _emitPoolCreatedEvents(
        address pool,
        IERC20 projectToken,
        IERC20 reserveToken,
        MigrationParams memory migrationParams,
        bool hasMigration
    ) internal {
        emit LBPoolCreated(pool, projectToken, reserveToken);

        if (hasMigration) {
            emit MigrationParamsSet(
                pool,
                migrationParams.lockDurationAfterMigration,
                migrationParams.bptPercentageToMigrate,
                migrationParams.migrationWeightProjectToken,
                migrationParams.migrationWeightReserveToken
            );
        }
    }
}
