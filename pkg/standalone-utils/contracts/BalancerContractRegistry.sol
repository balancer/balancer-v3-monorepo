// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import {
    IBalancerContractRegistry
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerContractRegistry.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

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

        emit BalancerContractRegistered(contractType, contractAddress, contractName);
    }

    /// @inheritdoc IBalancerContractRegistry
    function deprecateBalancerContract(address contractAddress) external authenticate {
        ContractStatus memory status = _contractStatus[contractAddress];

        // Check that the address has been registered.
        if (status.exists == false) {
            revert ContractNotRegistered(contractAddress);
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
