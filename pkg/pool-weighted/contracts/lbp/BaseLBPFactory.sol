// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

/**
 * @notice LBPool Factory.
 * @dev This is a factory specific to LBPools, allowing only two tokens and restricting the LBP to a single token sale,
 * with parameters specified on deployment.
 */
abstract contract BaseLBPFactory is IPoolVersion, ReentrancyGuardTransient, Version {
    // LBPs are constrained to two tokens: project (the token being sold), and reserve (e.g., USDC or WETH).
    uint256 internal constant _TWO_TOKENS = 2;

    // Set a boundary on the maximum lock duration, as a safeguard against accidentally locking it forever.
    uint256 internal constant _MAX_BPT_LOCK_DURATION = 365 days;

    // Set a boundary on the minimum pool value to migrate; otherwise owners could circumvent the liquidity guarantee
    // by migrating a trivial amount of the proceeds. Note that LBP participants should also note the lock duration;
    // a very short lock time would have a similar effect.
    uint256 internal constant _MIN_RESERVE_TOKEN_MIGRATION_WEIGHT = 20e16; // 20%

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

    /// @notice The owner is the zero address.
    error InvalidOwner();

    /// @notice The sum of migrated weights is not equal to 1.
    error InvalidMigrationWeights();

    /// @notice The percentage of BPT to migrate is greater than 100%.
    error InvalidBptPercentageToMigrate();

    /// @notice The BPT lock duration is greater than the maximum allowed.
    error InvalidBptLockDuration();

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

    function _buildTokenConfig(
        IERC20 projectToken,
        IERC20 reserveToken
    ) internal pure returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](_TWO_TOKENS);

        (tokenConfig[0].token, tokenConfig[1].token) = projectToken < reserveToken
            ? (projectToken, reserveToken)
            : (reserveToken, projectToken);
    }
}
