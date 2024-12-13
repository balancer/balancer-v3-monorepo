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
 * `getBalancerContract(type, name)` for the second.
 *
 * Note that the `SingletonAuthentication` base contract provides `getVault`, so it is also possible to ask this
 * contract for the Vault address, so it doesn't need to be a type.
 */
contract BalancerContractRegistry is IBalancerContractRegistry, SingletonAuthentication {
    // ContractId is the hash of ContractType + ContractName.
    mapping(bytes32 contractId => address addr) private _contractRegistry;

    // Given an address, store the contract state (i.e., active or deprecated).
    mapping(address addr => ContractStatus status) private _contractStatus;

    // We also need to look up address/type combinations (without the name).
    mapping(address addr => mapping(ContractType contractType => bool exists)) private _contractTypes;

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
     * registerBalancerContract(ContractType.POOL_FACTORY, 'WeightedPool', 0x201efd508c8DfE9DE1a13c2452863A78CB2a86Cc);
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
     * replaceBalancerContract(ContractType.POOL_FACTORY, 'WeightedPool', 0x9FC3da866e7DF3a1c57adE1a97c9f00a70f010c8);
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
        if (contractAddress == address(0)) {
            revert ZeroContractAddress();
        }

        if (bytes(contractName).length == 0) {
            revert InvalidContractName();
        }

        bytes32 contractId = _getContractId(contractType, contractName);

        if (_contractRegistry[contractId] != address(0)) {
            revert ContractAlreadyRegistered(contractType, contractName);
        }

        // Edge case: Cannot register a new "alias" (i.e., type/name) for an address if it's already been deprecated.
        ContractStatus memory status = _contractStatus[contractAddress];
        if (status.exists && status.active == false) {
            revert ContractAlreadyDeprecated(contractAddress);
        }

        // Store the address in the registry, under the unique combination of type and name.
        _contractRegistry[contractId] = contractAddress;

        // Record the address as active. The `exists` flag enables differentiating between unregistered and deprecated
        // addresses.
        _contractStatus[contractAddress] = ContractStatus({ exists: true, active: true });

        // Enable querying by address + type (without the name, as a single address could be associated with multiple
        // types and names).
        _contractTypes[contractAddress][contractType] = true;

        emit BalancerContractRegistered(contractType, contractName, contractAddress);
    }

    /// @inheritdoc IBalancerContractRegistry
    function deprecateBalancerContract(address contractAddress) external authenticate {
        ContractStatus memory status = _contractStatus[contractAddress];

        // Check that the address has been registered.
        if (status.exists == false) {
            revert ContractNotRegistered();
        }

        // If it was registered, check that it has not already been deprecated.
        if (status.active == false) {
            revert ContractAlreadyDeprecated(contractAddress);
        }

        // Set active to false to indicate that it's now deprecated. This is currently a one-way operation, since
        // deprecation is considered permanent. For instance, calling `disable` to deprecate a factory (preventing
        // new pool creation) is permanent.
        status.active = false;
        _contractStatus[contractAddress] = status;

        emit BalancerContractDeprecated(contractAddress);
    }

    /// @inheritdoc IBalancerContractRegistry
    function replaceBalancerContract(
        ContractType contractType,
        string memory contractName,
        address newContract
    ) external authenticate {
        if (newContract == address(0)) {
            revert ZeroContractAddress();
        }

        // Ensure the type/name combination was already registered.
        bytes32 contractId = _getContractId(contractType, contractName);
        address existingContract = _contractRegistry[contractId];
        if (existingContract == address(0)) {
            revert ContractNotRegistered();
        }

        _contractRegistry[contractId] = newContract;
        _contractStatus[newContract] = ContractStatus({ exists: true, active: true });
        _contractTypes[newContract][contractType] = true;

        emit BalancerContractReplaced(contractType, contractName, existingContract, newContract);
    }

    /// @inheritdoc IBalancerContractRegistry
    function isActiveBalancerContract(ContractType contractType, address contractAddress) external view returns (bool) {
        // Ensure the address was registered as the given type - and that it's still active.
        return _contractTypes[contractAddress][contractType] && _contractStatus[contractAddress].active;
    }

    /// @inheritdoc IBalancerContractRegistry
    function getBalancerContract(
        ContractType contractType,
        string memory contractName
    ) external view returns (address contractAddress, bool active) {
        bytes32 contractId = _getContractId(contractType, contractName);

        contractAddress = _contractRegistry[contractId];
        active = _contractStatus[contractAddress].active;
    }

    function _getContractId(ContractType contractType, string memory contractName) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(contractType, contractName));
    }
}
