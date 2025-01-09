// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import {
    IBalancerContractRegistry,
    ContractType
} from "@balancer-labs/v3-interfaces/contracts/vault/IBalancerContractRegistry.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "./SingletonAuthentication.sol";

/**
 * @notice On-chain registry of standard Balancer contracts.
 * @dev Maintain a registry of official Balancer Factories, Routers, Hooks, and valid ERC4626 tokens, for two main
 * purposes. The first is to support the many instances where we need to know that a contract is "trusted" (i.e.,
 * is safe and behaves in the required manner). For instance, some hooks depend critically on the identity of the
 * msg.sender, which must be passed down through the Router. Since Routers are permissionless, a malicious one could
 * spoof the sender and "fool" the hook. The hook must therefore "trust" the Router.
 *
 * It is also important for the front-end to know when a particular wrapped token should be used with buffers. Not all
 * "ERC4626" wrapped tokens are fully conforming, and buffer operations with non-conforming tokens may fail in various
 * unexpected ways. It is not enough to simply check whether a buffer exists (e.g., by calling `getBufferAsset`),
 * since best practice is for the pool creator to initialize buffers for all such tokens regardless. They are
 * permissionless, and could otherwise be initialized by anyone in unexpected ways. This registry could be used to
 * keep track of "known good" buffers, such that `isActiveBalancerContract(ContractType.ERC4626, <address>)` returns
 * true for fully-compliant tokens with properly initialized buffers.
 *
 * Current solutions involve passing in the address of the trusted Router on deployment: but what if it needs to
 * support multiple Routers? Or if the Router is deprecated and replaced? Instead, we can pass the registry address,
 * and query this contract to determine whether the Router is a "trusted" one.
 *
 * The second use case is for off-chain queries, or other protocols that need to easily determine, say, the "latest"
 * Weighted Pool Factory. This contract provides `isActiveBalancerContract(type, address)` for the first case, and
 * `getBalancerContract(type, name)` for the second. It is also possible to query all known information about an
 * address, using `getBalancerContractInfo(address)`, which returns a struct with the detailed state.
 *
 * Note that the `SingletonAuthentication` base contract provides `getVault`, so it is also possible to ask this
 * contract for the Vault address, so it doesn't need to be a type.
 */
contract BalancerContractRegistry is IBalancerContractRegistry, SingletonAuthentication {
    // ContractId is the hash of contract name. Names must be unique (cannot have the same name with different types).
    mapping(bytes32 contractId => address addr) private _contractRegistry;

    // Given an address, store the contract state (i.e., type, and active or deprecated).
    //
    // Conceptually, we maintain a <unique name> => <unique address> => <contract info> registry of contracts.
    // The only thing that can change is the `isActive` flag, when a contract is deprecated. If a contract is
    // registered in error (e.g., wrong type or address), the remedy is to deregister (delete) it, and then register
    // the correct one.
    //
    // We also maintain a registry of aliases: <unique alias> => <unique registered address>, where the target address
    // must be in the main registry, and the alias cannot match a unique registered contract name. Aliases can be
    // overwritten (e.g., when the `WeightedPool` alias migrates from v2 to v3). See `_contractAliases` below.
    mapping(address addr => ContractInfo info) private _contractInfo;

    // ContractAliasId is the hash of the alias (e.g., "WeightedPool").
    // This is separate from the main contract registry to enforce different rules (e.g., prevent corrupting the
    // contract state by overwriting a registry entry with an "alias" that matches a different contract).
    mapping(bytes32 contractAliasId => address addr) private _contractAliases;

    /// @dev A `_contractRegistry` entry has no corresponding `_contractInfo`. Should never happen.
    error InconsistentState();

    constructor(IVault vault) SingletonAuthentication(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /*
     * Example usage:
     *
     * // Register both the named version and the "latest" Weighted Pool Factory.
     * registerBalancerContract(
     *      ContractType.POOL_FACTORY, '20241205-v3-weighted-pool', 0x201efd508c8DfE9DE1a13c2452863A78CB2a86Cc
     * );
     * addOrUpdateBalancerContractAlias('WeightedPool', 0x201efd508c8DfE9DE1a13c2452863A78CB2a86Cc);
     *
     * // Register the Routers (two of them anyway).
     * registerBalancerContract(ContractType.ROUTER, '20241205-v3-router', 0x5C6fb490BDFD3246EB0bB062c168DeCAF4bD9FDd);
     * registerBalancerContract(
     *      ContractType.ROUTER, '20241205-v3-batch-router', 0x136f1EFcC3f8f88516B9E94110D56FDBfB1778d1
     * );
     *
     * // Now, hooks that require trusted routers can be deployed with the registry address, and query the router to
     * // see whether it's "trusted" (i.e., registered by governance):
     *
     * isActiveBalancerContract(ContractType.ROUTER, 0x5C6fb490BDFD3246EB0bB062c168DeCAF4bD9FDd) would return true.
     *
     * Off-chain processes that wanted to know the current address of the Weighted Pool Factory could query by either
     * name:
     *
     * (address, active) = getBalancerContract(ContractType.POOL_FACTORY, '20241205-v3-weighted-pool');
     * (address, active) = getBalancerContract(ContractType.POOL_FACTORY, 'WeightedPool');
     *
     * These would return the same result.
     *
     * If we replaced `20241205-v3-weighted-pool` with `20250107-v3-weighted-pool-v2`, governance would call:
     *
     * deprecateBalancerContract(0x201efd508c8DfE9DE1a13c2452863A78CB2a86Cc);
     * registerBalancerContract(
     *      ContractType.POOL_FACTORY, '20250107-v3-weighted-pool-v2', 0x9FC3da866e7DF3a1c57adE1a97c9f00a70f010c8)
     * );
     * addOrUpdateBalancerContractAlias('WeightedPool', 0x9FC3da866e7DF3a1c57adE1a97c9f00a70f010c8);
     *
     * At that point,
     * getBalancerContract(ContractType.POOL_FACTORY, '20241205-v3-weighted-pool') returns active=false,
     * isActiveBalancerContract(ContractType.POOL_FACTORY, 0x201efd508c8DfE9DE1a13c2452863A78CB2a86Cc) returns false,
     * getBalancerContract(ContractType.POOL_FACTORY, 'WeightedPool') returns the v2 address (and active=true).
     */

    /// @inheritdoc IBalancerContractRegistry
    function registerBalancerContract(
        ContractType contractType,
        string memory contractName,
        address contractAddress
    ) external authenticate {
        // Ensure arguments are valid.
        if (contractAddress == address(0)) {
            revert ZeroContractAddress();
        }

        if (bytes(contractName).length == 0) {
            revert InvalidContractName();
        }

        // Ensure address isn't already in use.
        ContractInfo memory info = _contractInfo[contractAddress];
        if (info.isRegistered) {
            revert AddressAlreadyRegistered(info.contractType, contractAddress);
        }

        // Ensure name isn't already in use (including as an alias).
        bytes32 contractId = _ensureUniqueName(contractName, true);

        // Store the address in the registry, under the unique name.
        _contractRegistry[contractId] = contractAddress;

        // Record the address as active. The `isActive` flag enables differentiating between unregistered and deprecated
        // addresses.
        _contractInfo[contractAddress] = ContractInfo({
            contractType: contractType,
            isRegistered: true,
            isActive: true
        });

        emit BalancerContractRegistered(contractType, contractName, contractAddress);
    }

    /// @inheritdoc IBalancerContractRegistry
    function deregisterBalancerContract(string memory contractName) external authenticate {
        // Ensure the name is registered
        bytes32 contractId = _getContractId(contractName);
        address contractAddress = _contractRegistry[contractId];

        if (contractAddress == address(0)) {
            revert ContractNotRegistered();
        }

        ContractInfo memory info = _contractInfo[contractAddress];
        // This should be impossible: the registry and info mappings must be in sync.
        if (info.isRegistered == false) {
            revert InconsistentState();
        }

        delete _contractRegistry[contractId];
        delete _contractInfo[contractAddress];

        emit BalancerContractDeregistered(info.contractType, contractName, contractAddress);
    }

    /// @inheritdoc IBalancerContractRegistry
    function deprecateBalancerContract(address contractAddress) external authenticate {
        ContractInfo memory info = _contractInfo[contractAddress];

        // Check that the address has been registered.
        if (info.isRegistered == false) {
            revert ContractNotRegistered();
        }

        // If it was registered, check that it has not already been deprecated.
        if (info.isActive == false) {
            revert ContractAlreadyDeprecated(contractAddress);
        }

        // Set active to false to indicate that it's now deprecated. This is currently a one-way operation, since
        // deprecation is considered permanent. For instance, calling `disable` to deprecate a factory (preventing
        // new pool creation) is permanent.
        info.isActive = false;
        _contractInfo[contractAddress] = info;

        emit BalancerContractDeprecated(contractAddress);
    }

    /// @inheritdoc IBalancerContractRegistry
    function addOrUpdateBalancerContractAlias(
        string memory contractAlias,
        address contractAddress
    ) external authenticate {
        // Ensure arguments are valid.
        if (bytes(contractAlias).length == 0) {
            revert InvalidContractName();
        }

        if (contractAddress == address(0)) {
            revert ZeroContractAddress();
        }

        // Ensure the address was already registered.
        ContractInfo memory info = _contractInfo[contractAddress];
        if (info.isRegistered == false) {
            revert ContractNotRegistered();
        }

        // Ensure the proposed alias is not in use (i.e., no collision with existing registered contracts).
        // It can match an existing alias: that's the "update" case. For instance, if we wanted to migrate
        // the `WeightedPool` alias from v2 to v3. If the name is not already in `_contractAliases`, we are
        // adding a new alias.
        bytes32 contractId = _ensureUniqueName(contractAlias, false);

        // This will either add a new or overwrite an existing alias.
        _contractAliases[contractId] = contractAddress;

        emit ContractAliasUpdated(contractAlias, contractAddress);
    }

    /// @inheritdoc IBalancerContractRegistry
    function isActiveBalancerContract(ContractType contractType, address contractAddress) external view returns (bool) {
        ContractInfo memory info = _contractInfo[contractAddress];

        // Ensure the address was registered as the given type - and that it's still active.
        return info.isActive && info.contractType == contractType;
    }

    /// @inheritdoc IBalancerContractRegistry
    function getBalancerContract(
        ContractType contractType,
        string memory contractName
    ) external view returns (address contractAddress, bool isActive) {
        bytes32 contractId = _getContractId(contractName);
        address registeredAddress = _contractRegistry[contractId];

        // Also check the aliases, if not found in the primary registry.
        if (registeredAddress == address(0)) {
            registeredAddress = _contractAliases[contractId];
        }

        ContractInfo memory info = _contractInfo[registeredAddress];
        // It is possible to register a contract and alias, then deregister the contract, leaving a "stale" alias
        // reference. In this case, `isRegistered` will be false. Only return the contract address if it is still
        // valid and of the correct type.
        if (info.isRegistered && info.contractType == contractType) {
            contractAddress = registeredAddress;
            isActive = info.isActive;
        }
    }

    /// @inheritdoc IBalancerContractRegistry
    function getBalancerContractInfo(address contractAddress) external view returns (ContractInfo memory info) {
        return _contractInfo[contractAddress];
    }

    function _ensureUniqueName(
        string memory contractName,
        bool includeAliases
    ) internal view returns (bytes32 contractId) {
        contractId = _getContractId(contractName);

        // Check both the registered names and aliases to ensure this name is not a duplicate.
        address existingContract = _contractRegistry[contractId];
        if (includeAliases && existingContract == address(0)) {
            existingContract = _contractAliases[contractId];
        }

        if (existingContract != address(0)) {
            ContractInfo memory info = _contractInfo[existingContract];

            revert ContractAlreadyRegistered(info.contractType, contractName);
        }
    }

    function _getContractId(string memory contractName) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(contractName));
    }
}
