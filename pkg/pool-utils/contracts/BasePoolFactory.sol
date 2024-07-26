// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    TokenConfig,
    PoolRoleAccounts,
    LiquidityManagement
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    SingletonAuthentication
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/SingletonAuthentication.sol";
import { FactoryWidePauseWindow } from "@balancer-labs/v3-solidity-utils/contracts/helpers/FactoryWidePauseWindow.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

/**
 * @notice Base contract for Pool factories.
 *
 * Pools are deployed from factories to allow third parties to more easiliy reason about them. Unknown Pools may have
 * arbitrary logic: being able to assert that a Pool's behavior follows certain rules (those imposed by the contracts
 * created by the factory) is very powerful.
 *
 * Note that in v3, the factory alone is not enough to ensure the safety of a pool. v3 pools can have arbitrary hook
 * contracts, rate providers, complex tokens, and configuration that significantly impacts pool behavior. Specialty
 * factories can be designed to limit their pools range of behavior (e.g., weighted 80/20 factories where the token
 * count and weights are fixed).
 *
 * Since we expect to release new versions of pool types regularly - and the blockchain is forever - versioning will
 * become increasingly important. Governance can deprecate a factory by calling `disable`, which will permanently
 * prevent the creation of any future pools from the factory.
 */
abstract contract BasePoolFactory is IBasePoolFactory, SingletonAuthentication, FactoryWidePauseWindow {
    mapping(address => bool) private _isPoolFromFactory;
    bool private _disabled;

    // Store the creationCode of the contract to be deployed by create3.
    bytes private _creationCode;

    /// @dev A pool creator was specified for a pool from a Balancer core pool type.
    error StandardPoolWithCreator();

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        bytes memory creationCode
    ) SingletonAuthentication(vault) FactoryWidePauseWindow(pauseWindowDuration) {
        _creationCode = creationCode;
    }

    /// @inheritdoc IBasePoolFactory
    function isPoolFromFactory(address pool) external view returns (bool) {
        return _isPoolFromFactory[pool];
    }

    /// @inheritdoc IBasePoolFactory
    function isDisabled() public view returns (bool) {
        return _disabled;
    }

    /// @inheritdoc IBasePoolFactory
    function getDeploymentAddress(bytes32 salt) public view returns (address) {
        return CREATE3.getDeployed(_computeFinalSalt(salt));
    }

    /// @inheritdoc IBasePoolFactory
    function disable() external authenticate {
        _ensureEnabled();

        _disabled = true;

        emit FactoryDisabled();
    }

    function _ensureEnabled() internal view {
        if (isDisabled()) {
            revert Disabled();
        }
    }

    function _registerPoolWithFactory(address pool) internal virtual {
        _ensureEnabled();

        _isPoolFromFactory[pool] = true;

        emit PoolCreated(pool);
    }

    /**
     * @dev Factories that require a custom-calculated salt can override to replace this default salt processing.
     * By default, the pool address determinants include the sender and chain id, as well as the user-provided salt,
     * so contracts will generally not have the same address on different L2s.
     */
    function _computeFinalSalt(bytes32 salt) internal view virtual returns (bytes32) {
        return keccak256(abi.encode(msg.sender, block.chainid, salt));
    }

    function _create(bytes memory constructorArgs, bytes32 salt) internal returns (address pool) {
        pool = CREATE3.deploy(_computeFinalSalt(salt), abi.encodePacked(_creationCode, constructorArgs), 0);

        _registerPoolWithFactory(pool);
    }

    function _registerPoolWithVault(
        address pool,
        TokenConfig[] memory tokens,
        uint256 swapFeePercentage,
        bool protocolFeeExempt,
        PoolRoleAccounts memory roleAccounts,
        address poolHooksContract,
        LiquidityManagement memory liquidityManagement
    ) internal {
        getVault().registerPool(
            pool,
            tokens,
            swapFeePercentage,
            getNewPoolPauseWindowEndTime(),
            protocolFeeExempt,
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );
    }

    /// @notice A common place to retrieve a default hooks contract. Currently set to address(0) (i.e. no hooks).
    function getDefaultPoolHooksContract() public pure returns (address) {
        return address(0);
    }

    /**
     * @notice Convenience function for constructing a LiquidityManagement object.
     * @dev Users can call this to create a structure with all false arguments, then set the ones they need to true.
     */
    function getDefaultLiquidityManagement() public pure returns (LiquidityManagement memory liquidityManagement) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
