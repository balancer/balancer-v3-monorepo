// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import { ILBPMigrationRouter } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPMigrationRouter.sol";
import { TokenConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ILBPool, LBPParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { LBPoolLib } from "../lib/LBPoolLib.sol";
import { LBPool } from "./LBPool.sol";

/**
 * @notice LBPool Factory.
 * @dev This is a factory specific to LBPools, allowing only two tokens and restricting the LBP to a single token sale,
 * with parameters specified on deployment.
 */
contract LBPoolFactory is IPoolVersion, ReentrancyGuardTransient, BasePoolFactory, Version {
    // LBPs are constrained to two tokens: project (the token being sold), and reserve (e.g., USDC or WETH).
    uint256 private constant _TWO_TOKENS = 2;

    uint256 private constant _MAX_BPT_LOCK_DURATION = 365 days;

    uint256 private constant _MIN_RESERVE_TOKEN_MIGRATION_WEIGHT = 20e16; // 20%

    string private _poolVersion;

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
     * @param bptLockDuration The duration for which the BPT will be locked after migration
     * @param bptPercentageToMigrate The percentage of the BPT to migrate from the LBP to the new weighted pool
     * @param migrationWeightProjectToken The weight of the project token
     * @param migrationWeightReserveToken The weight of the reserve token
     */
    event MigrationParamsSet(
        address indexed pool,
        uint256 bptLockDuration,
        uint256 bptPercentageToMigrate,
        uint256 migrationWeightProjectToken,
        uint256 migrationWeightReserveToken
    );

    /// @notice The zero address was given for the trusted router.
    error InvalidTrustedRouter();

    /// @notice The owner is the zero address.
    error InvalidOwner();

    /// @notice The sum of migrated weights is not equal to 1.
    error InvalidMigrationWeights();

    /// @notice The percentage of BPT to migrate is greater than 100%.
    error InvalidBptPercentageToMigrate();

    /// @notice The BPT lock duration is greater than the maximum allowed.
    error InvalidBptLockDuration();

    struct MigrationParams {
        uint256 bptLockDuration;
        uint256 bptPercentageToMigrate;
        uint256 migrationWeightProjectToken;
        uint256 migrationWeightReserveToken;
    }

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address trustedRouter,
        address migrationRouter
    ) BasePoolFactory(vault, pauseWindowDuration, type(LBPool).creationCode) Version(factoryVersion) {
        if (trustedRouter == address(0)) {
            revert InvalidTrustedRouter();
        }

        // LBPools are deployed with a router known to reliably report the originating address on operations.
        // This is used to ensure that only the owner can add liquidity to an LBP.
        _trustedRouter = trustedRouter;
        _migrationRouter = migrationRouter;

        _poolVersion = poolVersion;
    }

    /// @inheritdoc IPoolVersion
    function getPoolVersion() external view returns (string memory) {
        return _poolVersion;
    }

    /// @notice Returns trusted router, which is the gateway to add liquidity to the pool.
    function getTrustedRouter() external view returns (address) {
        return _trustedRouter;
    }

    /// @notice Returns the migration router, which is used to migrate liquidity from an LBP to a new weighted pool.
    function getMigrationRouter() external view returns (address) {
        return _migrationRouter;
    }

    /**
     * @notice Deploys a new `LBPool`.
     * @dev This method does not support native ETH management; WETH needs to be used instead.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param lbpParams The LBP configuration (see ILBPool for the struct definition)
     * @param swapFeePercentage Initial swap fee percentage (bound by the WeightedPool range)
     * @param salt The salt value that will be passed to create3 deployment
     * @param poolCreator Address that will be registered as the pool creator, which receives a cut of the protocol fees
     */
    function create(
        string memory name,
        string memory symbol,
        LBPParams memory lbpParams,
        uint256 swapFeePercentage,
        bytes32 salt,
        address poolCreator
    ) public nonReentrant returns (address pool) {
        MigrationParams memory migrationParams;
        pool = _createPool(name, symbol, lbpParams, swapFeePercentage, salt, false, poolCreator, migrationParams);
    }

    /**
     * @notice Deploys a new `LBPool` with migration.
     * @dev This method does not support native ETH management; WETH needs to be used instead.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param lbpParams The LBP configuration (see ILBPool for the struct definition)
     * @param swapFeePercentage Initial swap fee percentage (bound by the WeightedPool range)
     * @param salt The salt value that will be passed to create3 deployment
     * @param poolCreator Address that will be registered as the pool creator, which receives a cut of the protocol fees
     * @param bptLockDuration The duration for which the BPT will be locked after migration
     * @param bptPercentageToMigrate The percentage of the BPT to migrate from the LBP to the new weighted pool
     * @param migrationWeightProjectToken The weight of the project token
     * @param migrationWeightReserveToken The weight of the reserve token
     */
    function createWithMigration(
        string memory name,
        string memory symbol,
        LBPParams memory lbpParams,
        uint256 swapFeePercentage,
        bytes32 salt,
        address poolCreator,
        uint256 bptLockDuration,
        uint256 bptPercentageToMigrate,
        uint256 migrationWeightProjectToken,
        uint256 migrationWeightReserveToken
    ) public nonReentrant returns (address pool) {
        MigrationParams memory migrationParams = MigrationParams({
            bptLockDuration: bptLockDuration,
            bptPercentageToMigrate: bptPercentageToMigrate,
            migrationWeightProjectToken: migrationWeightProjectToken,
            migrationWeightReserveToken: migrationWeightReserveToken
        });

        pool = _createPool(name, symbol, lbpParams, swapFeePercentage, salt, true, poolCreator, migrationParams);
    }

    function _createPool(
        string memory name,
        string memory symbol,
        LBPParams memory lbpParams,
        uint256 swapFeePercentage,
        bytes32 salt,
        bool hasMigration,
        address poolCreator,
        MigrationParams memory migrationParams
    ) internal returns (address pool) {
        if (lbpParams.owner == address(0)) {
            revert InvalidOwner();
        }

        PoolRoleAccounts memory roleAccounts;

        // This account can change the static swap fee for the pool.
        roleAccounts.swapFeeManager = lbpParams.owner;
        roleAccounts.poolCreator = poolCreator;

        // Validate weight parameters and temporal constraints prior to deployment.
        // This validation is duplicated in the pool contract but performed here to surface precise error messages,
        // as create2 would otherwise mask the underlying revert reason.
        LBPoolLib.verifyWeightUpdateParameters(
            lbpParams.startTime,
            lbpParams.endTime,
            lbpParams.projectTokenStartWeight,
            lbpParams.reserveTokenStartWeight,
            lbpParams.projectTokenEndWeight,
            lbpParams.reserveTokenEndWeight
        );

        // If there is no migration, the migration parameters don't need to be validated.
        if (hasMigration) {
            uint256 totalTokenWeight = migrationParams.migrationWeightProjectToken +
                migrationParams.migrationWeightReserveToken;
            if (
                (totalTokenWeight != FixedPoint.ONE ||
                    migrationParams.migrationWeightProjectToken == 0 ||
                    migrationParams.migrationWeightReserveToken < _MIN_RESERVE_TOKEN_MIGRATION_WEIGHT)
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
            if (migrationParams.bptLockDuration > _MAX_BPT_LOCK_DURATION || migrationParams.bptLockDuration == 0) {
                revert InvalidBptLockDuration();
            }
        }

        address migrationRouterOrZero = hasMigration ? _migrationRouter : address(0);

        pool = _create(
            abi.encode(
                name,
                symbol,
                lbpParams,
                getVault(),
                _trustedRouter,
                migrationRouterOrZero,
                _poolVersion,
                migrationParams.bptLockDuration,
                migrationParams.bptPercentageToMigrate,
                migrationParams.migrationWeightProjectToken,
                migrationParams.migrationWeightReserveToken
            ),
            salt
        );

        emit LBPoolCreated(pool, lbpParams.projectToken, lbpParams.reserveToken);

        if (hasMigration) {
            emit MigrationParamsSet(
                pool,
                migrationParams.bptLockDuration,
                migrationParams.bptPercentageToMigrate,
                migrationParams.migrationWeightProjectToken,
                migrationParams.migrationWeightReserveToken
            );
        }

        _registerPoolWithVault(
            pool,
            _buildTokenConfig(lbpParams.projectToken, lbpParams.reserveToken),
            swapFeePercentage,
            false, // not exempt from protocol fees
            roleAccounts,
            pool, // register the pool itself as the hook contract
            getDefaultLiquidityManagement()
        );
    }

    function _buildTokenConfig(
        IERC20 projectToken,
        IERC20 reserveToken
    ) private pure returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](_TWO_TOKENS);

        (tokenConfig[0].token, tokenConfig[1].token) = projectToken < reserveToken
            ? (projectToken, reserveToken)
            : (reserveToken, projectToken);
    }
}
