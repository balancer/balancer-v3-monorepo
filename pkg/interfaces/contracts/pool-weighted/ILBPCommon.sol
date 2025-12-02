// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "../vault/IBasePool.sol";
import { IVault } from "../vault/IVault.sol";

/**
 * @notice Parameters common to all LBP types.
 * @dev These parameters are immutable, representing the configuration of a single token sale, running from `startTime`
 * to `endTime`. Swaps may only occur while the sale is active. If `blockProjectTokenSwapsIn` is true, users may only
 * purchase project tokens with the reserve currency.
 *
 * @param name The name of the pool
 * @param symbol The symbol of the pool
 * @param owner Address of the LBP owner (and sole LP)
 * @param projectToken The token being sold
 * @param reserveToken The token used to buy the project token (e.g., USDC or WETH)
 * @param startTime The timestamp at the beginning of the sale - initialization/funding must occur before this time
 * @param endTime the timestamp at the end of the sale - withdrawal of proceeds becomes possible after this time
 * @param blockProjectTokenSwapsIn If set, the pool only supports one-way "token distribution"
 */
struct LBPCommonParams {
    string name;
    string symbol;
    address owner;
    IERC20 projectToken;
    IERC20 reserveToken;
    uint256 startTime;
    uint256 endTime;
    bool blockProjectTokenSwapsIn;
}

/**
 * @notice Parameters related to migration to a Weighted Pool after the sale is completed.
 * @dev `bptPercentageToMigrate` is immutable to provide a liquidity guarantee to token buyers. Choose its value
 * carefully: a lower percentage with a shorter lock may be preferable if sale performance is uncertain.
 *
 * @param migrationRouter The address of the router used for migration to a Weighted Pool after the sale
 * @param lockDurationAfterMigration The duration for which the BPT will be locked after migration
 * @param bptPercentageToMigrate The percentage of the BPT to migrate from the LBP to the new weighted pool
 * @param migrationWeightProjectToken The weight of the project token
 * @param migrationWeightReserveToken The weight of the reserve token
 */
struct MigrationParams {
    address migrationRouter;
    uint256 lockDurationAfterMigration;
    uint256 bptPercentageToMigrate;
    uint256 migrationWeightProjectToken;
    uint256 migrationWeightReserveToken;
}

/**
 * @notice Parameters passed down from the factory and passed to the pool on deployment.
 * @dev This struct was factored out initially because of stack-too-deep, but also makes the interface cleaner.
 * @param vault The address of the Balancer Vault
 * @param trustedRouter The address of the trusted router (i.e., one that reliably stores the real sender)
 * @param poolVersion The pool version deployed by the factory
 */
struct FactoryParams {
    IVault vault;
    address trustedRouter;
    string poolVersion;
}

/// @notice Common basic interface for all LBPool types.
interface ILBPCommon is IBasePool {
    /**
     * @notice Get the project token for this LBP.
     * @dev This is the token being distributed through the sale. It is also available in the immutable data, but this
     * getter is provided as a convenience for those who only need the project token address.
     *
     * @return projectToken The address of the project token
     */
    function getProjectToken() external view returns (IERC20 projectToken);

    /**
     * @notice Get the reserve token for this LBP.
     * @dev This is the token exchanged for the project token (usually a stablecoin or WETH). It is also available in
     * the immutable data, but this getter is provided as a convenience for those who only need the reserve token
     * address.
     *
     * @return reserveToken The address of the reserve token
     */
    function getReserveToken() external view returns (IERC20 reserveToken);

    /**
     * @notice Convenience function to return the token indices (determined by the addresses).
     * @return projectTokenIndex Index of the project token in the pool
     * @return reserveTokenIndex Index of the reserve token in the pool
     */
    function getTokenIndices() external view returns (uint256 projectTokenIndex, uint256 reserveTokenIndex);

    /**
     * @notice Indicate whether project tokens can be sold back into the pool.
     * @dev Note that theoretically, anyone holding project tokens could create a new pool alongside the LBP that did
     * allow "selling" project tokens. This restriction only applies to the primary LBP.
     *
     * @return isProjectTokenSwapInBlocked If true, acquired project tokens cannot be traded for reserve in this pool
     */
    function isProjectTokenSwapInBlocked() external view returns (bool isProjectTokenSwapInBlocked);

    /**
     * @notice Returns the trusted router, which is used to initialize and seed the pool.
     * @return trustedRouter Address of the trusted router (i.e., one that reliably reports the sender)
     */
    function getTrustedRouter() external view returns (address trustedRouter);

    /**
     * @notice Returns the migration router used to migrate the liquidity.
     * @return migrationRouter Address of the migration router
     */
    function getMigrationRouter() external view returns (address migrationRouter);

    /**
     * @notice Retrieve the migration parameters for an LBP.
     * @return migrationParams The migration parameters (duration, successor Weighted Pool config)
     */
    function getMigrationParameters() external view returns (MigrationParams memory migrationParams);

    /**
     * @notice Indicate whether or not swaps are enabled for this pool.
     * @dev For LBPs, swaps are enabled during the token sale, between the start and end times. Note that this does
     * not check whether the pool or Vault is paused, which can only happen through governance action. This can be
     * checked using `getPoolConfig` on the Vault, or by calling `getLBPoolDynamicData` here.
     *
     * @return isSwapEnabled True if the sale is in progress
     */
    function isSwapEnabled() external view returns (bool isSwapEnabled);
}
