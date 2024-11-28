// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    TokenConfig,
    PoolRoleAccounts,
    LiquidityManagement
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { FactoryWidePauseWindow } from "@balancer-labs/v3-solidity-utils/contracts/helpers/FactoryWidePauseWindow.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

/**
 * @notice Base contract for Pool factories.
 *
 * Pools are deployed from factories to allow third parties to more easily reason about them. Unknown Pools may have
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
    mapping(address pool => bool isFromFactory) private _isPoolFromFactory;
    address[] private _pools;

    bool private _disabled;

    // Store the creationCode of the contract to be deployed by create3.
    bytes private _creationCode;

    /// @notice A pool creator was specified for a pool from a Balancer core pool type.
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
    function getPools(uint256 start, uint256 count) external view returns (address[] memory result) {
        uint256 length = _pools.length;
        require(start < length, "BasePoolFactory: start out of bounds");

        uint256 end = start + count;
        if (end > length) {
            count = length - start;
        }

        result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = _pools[start + i];
        }

        return result;
    }

    /// @inheritdoc IBasePoolFactory
    function isDisabled() public view returns (bool) {
        return _disabled;
    }

    /// @inheritdoc IBasePoolFactory
    function getDeploymentAddress(
        bytes memory constructorArgs,
        bytes32 salt
    ) public view returns (address deployAddress) {
        bytes memory creationCode = abi.encodePacked(_creationCode, constructorArgs);
        bytes32 creationCodeHash = keccak256(creationCode);
        bytes32 finalSalt = _computeFinalSalt(salt);

        address contractAddress = address(this);

        assembly {
            let ptr := mload(0x40)

            mstore(add(ptr, 0x40), creationCodeHash)
            mstore(add(ptr, 0x20), finalSalt)
            mstore(ptr, contractAddress)
            let start := add(ptr, 0x0b)
            mstore8(start, 0xff)
            deployAddress := keccak256(start, 85)
        }
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
        _pools.push(pool);

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
        bytes memory creationCode = abi.encodePacked(_creationCode, constructorArgs);
        bytes32 finalSalt = _computeFinalSalt(salt);
        assembly {
            pool := create2(0, add(creationCode, 32), mload(creationCode), finalSalt)
        }

        if (pool == address(0)) {
            // Bubble up inner revert reason
            // solhint-disable-next-line no-inline-assembly
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }

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
