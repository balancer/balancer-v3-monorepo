// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IBalancerContractRegistry {
    /// @notice Registered contracts must be one of these types.
    enum ContractType {
        POOL_FACTORY,
        ROUTER,
        HOOK
    }

    /**
     * @notice Contracts can be deprecated, so we store an active flag indicating the status.
     * @dev With two flags, we can differentiate between deprecated and non-existent.
     * @param exists This flag indicates whether there is an entry for the address or not
     * @param active If there is an entry, this flag indicates whether it is active or deprecated
     */
    struct ContractStatus {
        bool exists;
        bool active;
    }

    /**
     * @notice Emitted wen a new contract is registered.
     * @param contractType The type of contract being registered
     * @param contractName The name of the contract
     * @param contractAddress The address of the contract being registered
     */
    event BalancerContractRegistered(
        ContractType indexed contractType,
        string indexed contractName,
        address indexed contractAddress
    );

    /**
     * @notice Emitted when a new contract is deprecated.
     * @dev This sets the `active` flag to false.
     * @param contractAddress The address of the contract being deprecated
     */
    event BalancerContractDeprecated(address indexed contractAddress);

    /**
     * @notice Emitted when a new contract is deprecated.
     * @dev This sets the `active` flag to false.
     * @param contractType The type of contract being registered
     * @param contractName The name of the contract
     * @param existingContract The address of the old contract being replaced
     * @param newContract The address of new contract
     */
    event BalancerContractReplaced(
        ContractType indexed contractType,
        string indexed contractName,
        address existingContract,
        address newContract
    );

    /**
     * @notice The given type and name have already been registered.
     * @dev Note that the same address can be registered multiple times under different names. For instance, we might
     * register an address as both "Factory/20241205-v3-weighted-pool" and "Factory/WeightedPool", or
     * "Hook/StableSurgeHook" and "Router/StableSurgeHook". However, the combination of type and name must be unique.
     *
     * @param contractType The type of the contract
     * @param contractName The name of the contract
     */
    error ContractAlreadyRegistered(ContractType contractType, string contractName);

    /// @notice The contract being deprecated was never registered.
    error ContractNotRegistered();

    /**
     * @notice The contract being deprecated was registered, but already deprecated.
     * @param contractAddress The address of the contract to be deprecated
     */
    error ContractAlreadyDeprecated(address contractAddress);

    /// @notice Registered contracts cannot have the zero address.
    error ZeroContractAddress();

    /// @notice Registered contract names cannot be blank.
    error InvalidContractName();

    /**
     * @notice Register an official Balancer contract (e.g., a trusted router, standard pool factory, or hook).
     * @dev This is a permissioned function, and does only basic validation of the address (non-zero) and the name
     * (not blank). Governance must ensure this is called with valid information. Emits the
     * `BalancerContractRegistered` event if successful. Reverts if the name or address is invalid, or the type/name
     * combination has already been registered.
     *
     * @param contractType The type of contract being registered
     * @param contractName A text description of the contract (e.g., "WeightedPool")
     * @param contractAddress The address of the contract
     */
    function registerBalancerContract(
        ContractType contractType,
        string memory contractName,
        address contractAddress
    ) external;

    /**
     * @notice Deprecate an official Balancer contract.
     * @dev This is a permissioned function that sets the `active` flag to false. The same address might be registered
     * multiple times (i.e., unique combinations of types and names); deprecating the address will naturally apply to
     * all of them. Emits an `BalancerContractDeprecated` event if successful. Reverts if the address has not been
     * registered, or has already been deprecated.
     *
     * @param contractAddress The address of the contract being deregistered
     */
    function deprecateBalancerContract(address contractAddress) external;

    /**
     * @notice Migrate a named contract to a new address.
     * @dev This is a permissioned function, intended to address one edge case and one feature. The edge case is
     * handling mistakes. If an address is mistakenly registered (e.g., set to the address on a different chain),
     * this allows correction. The feature is supporting querying for the "latest" contract (e.g., the latest version
     * of `WeightedPoolFactory`), vs. having to know the exact version. If the "latest" contract address changes --
     * for instance, if we deprecated `v3-weighted-pool` and registered `v3-weighted-pool-v2`, we would need to
     * update `WeightedPoolFactory` to point to the v2 address. Normal registration would fail, as that combination
     * was already registered, pointing to v1.
     *
     * @param contractType The type of contract being replaced
     * @param contractName The name of the contract being replaced
     * @param newContractAddress The address of the contract that should replace the existing registration
     */
    function replaceBalancerContract(
        ContractType contractType,
        string memory contractName,
        address newContractAddress
    ) external;

    /**
     * @notice Determine whether an address is an official contract of the specified type.
     * @dev This is a permissioned function.
     * @param contractType The type of contract being renamed
     * @param contractAddress The address of the contract
     * @return success True if the given address is a registered and active contract of the specified type
     */
    function isActiveBalancerContract(
        ContractType contractType,
        address contractAddress
    ) external view returns (bool success);

    /**
     * @notice Lookup a registered contract by type and name
     * @dev This could target a particular version (e.g. `20241205-v3-weighted-pool`), or a contract name
     * (e.g., `WeightedPool`), which could return the "latest" WeightedPool deployment.
     *
     * @param contractType The type of the contract
     * @param contractName The name of the contract
     * @return contractAddress The address of the associated contract, if registered, or zero
     * @return active True if the address was registered and not deprecated
     */
    function getBalancerContract(
        ContractType contractType,
        string memory contractName
    ) external view returns (address contractAddress, bool active);
}
