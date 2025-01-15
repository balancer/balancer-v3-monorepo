// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Registered contracts must be one of these types.
enum ContractType {
    OTHER, // a blank entry will have a 0-value type, and it's safest to return this in that case
    POOL_FACTORY,
    ROUTER,
    HOOK,
    ERC4626
}

interface IBalancerContractRegistry {
    /**
     * @notice Store the state of a registered Balancer contract.
     * @dev Contracts can be deprecated, so we store an active flag indicating the status. With two flags, we can
     * differentiate between deprecated and non-existent. The same contract address can have multiple names, but
     * only one type. If a contract is legitimately multiple types (e.g., a hook that also acts as a router), set
     * the type to its "primary" function: hook, in this case. The "Other" type is intended as a catch-all for
     * things that don't find into the standard types (e.g., helper contracts).
     *
     * @param contractType The type of contract (e.g., Router or Hook)
     * @param isRegistered This flag indicates whether there is an entry for the associated address
     * @param isActive If there is an entry, this flag indicates whether it is active or deprecated
     */
    struct ContractInfo {
        ContractType contractType;
        bool isRegistered;
        bool isActive;
    }

    /**
     * @notice Emitted when a new contract is registered.
     * @param contractType The type of contract being registered
     * @param contractName The name of the contract being registered
     * @param contractAddress The address of the contract being registered
     */
    event BalancerContractRegistered(
        ContractType indexed contractType,
        string indexed contractName,
        address indexed contractAddress
    );

    /**
     * @notice Emitted when a new contract is deregistered (deleted).
     * @param contractType The type of contract being deregistered
     * @param contractName The name of the contract being deregistered
     * @param contractAddress The address of the contract being deregistered
     */
    event BalancerContractDeregistered(
        ContractType indexed contractType,
        string indexed contractName,
        address indexed contractAddress
    );

    /**
     * @notice Emitted when a registered contract is deprecated.
     * @dev This sets the `isActive` flag to false.
     * @param contractAddress The address of the contract being deprecated
     */
    event BalancerContractDeprecated(address indexed contractAddress);

    /**
     * @notice Emitted when an alias is added or updated.
     * @param contractAlias The alias name
     * @param contractAddress The address of the contract being deprecated
     */
    event ContractAliasUpdated(string indexed contractAlias, address indexed contractAddress);

    /**
     * @notice A contract has already been registered under the given address.
     * @dev Both names and addresses must be unique in the primary registration mapping. Though there are two mappings
     * to accommodate searching by either name or address, conceptually there is a single guaranteed-consistent
     * name => address => state mapping.
     *
     * @param contractType The contract type, provided for documentation purposes
     * @param contractAddress The address of the previously registered contract
     */
    error ContractAddressAlreadyRegistered(ContractType contractType, address contractAddress);

    /**
     * @notice A contract has already been registered under the given name.
     * @dev Note that names must be unique; it is not possible to register two contracts with the same name and
     * different types, or the same name and different addresses.
     *
     * @param contractType The registered contract type, provided for documentation purposes
     * @param contractName The name of the previously registered contract
     */
    error ContractNameAlreadyRegistered(ContractType contractType, string contractName);

    /**
     * @notice The proposed contract name has already been added as an alias.
     * @dev This could lead to inconsistent (or at least redundant) internal state if allowed.
     * @param contractName The name of the previously registered contract
     * @param contractAddress The address of the previously registered contract
     */
    error ContractNameInUseAsAlias(string contractName, address contractAddress);

    /**
     * @notice The proposed alias has already been registered as a contract.
     * @dev This could lead to inconsistent (or at least redundant) internal state if allowed.
     * @param contractType The registered contract type, provided for documentation purposes
     * @param contractName The name of the previously registered contract (and proposed alias)
     */
    error ContractAliasInUseAsName(ContractType contractType, string contractName);

    /**
     * @notice Thrown when attempting to deregister a contract that was not previously registered.
     * @param contractName The name of the unregistered contract
     */
    error ContractNameNotRegistered(string contractName);

    /**
     * @notice An operation that requires a valid contract specified an unrecognized address.
     * @dev A contract being deprecated was never registered, or the target of an alias isn't a previously
     * registered contract.
     *
     * @param contractAddress The address of the contract that was not registered
     */
    error ContractAddressNotRegistered(address contractAddress);

    /**
     * @notice Contracts can only be deprecated once.
     * @param contractAddress The address of the previously deprecated contract
     */
    error ContractAlreadyDeprecated(address contractAddress);

    /// @notice Cannot register or deprecate contracts, or add an alias targeting the zero address.
    error ZeroContractAddress();

    /// @notice Cannot register (or deregister) a contract with an empty string as a name.
    error InvalidContractName();

    /// @notice Cannot add an empty string as an alias.
    error InvalidContractAlias();

    /**
     * @notice Register an official Balancer contract (e.g., a trusted router, standard pool factory, or hook).
     * @dev This is a permissioned function, and does only basic validation of the address (non-zero) and the name
     * (not blank). Governance must ensure this is called with valid information. Emits the
     * `BalancerContractRegistered` event if successful. Reverts if either the name or address is invalid or
     * already in use.
     *
     * @param contractType The type of contract being registered
     * @param contractName A text description of the contract, usually the deployed version (e.g., "v3-pool-weighted")
     * @param contractAddress The address of the contract
     */
    function registerBalancerContract(
        ContractType contractType,
        string memory contractName,
        address contractAddress
    ) external;

    /**
     * @notice Deregister an official Balancer contract (e.g., a trusted router, standard pool factory, or hook).
     * @dev This is a permissioned function, and makes it possible to correct errors without complex update logic.
     * If a contract was registered with an incorrect type, name, or address, this allows governance to simply delete
     * it, and register it again with the correct data. It must start with the name, as this is the registry key,
     * required for complete deletion.
     *
     * Note that there might still be an alias targeting the address being deleted, but accessing it will just return
     * inactive, and this orphan alias can simply be overwritten with `addOrUpdateBalancerContractAlias` to point to
     * the correct address.
     *
     * @param contractName The name of the contract being deprecated (cannot be an alias)
     */
    function deregisterBalancerContract(string memory contractName) external;

    /**
     * @notice Deprecate an official Balancer contract.
     * @dev This is a permissioned function that sets the `isActive` flag to false in the contract info. It uses the
     * address instead of the name for maximum clarity, and to avoid having to handle aliases. Addresses and names are
     * enforced unique, so either the name or address could be specified in principle.
     *
     * @param contractAddress The address of the contract being deprecated
     */
    function deprecateBalancerContract(address contractAddress) external;

    /**
     * @notice Add an alias for a registered contract.
     * @dev This is a permissioned function to support querying by a contract alias. For instance, we might create a
     * `WeightedPool` alias meaning the "latest" version of the `WeightedPoolFactory`, so that off-chain users don't
     * need to track specific versions. Once added, an alias can also be updated to point to a different address
     * (e.g., when migrating from the v2 to the v3 weighted pool).
     *
     * @param contractAlias An alternate name that can be used to fetch a contract address
     * @param existingContract The target address of the contract alias
     */
    function addOrUpdateBalancerContractAlias(string memory contractAlias, address existingContract) external;

    /**
     * @notice Determine whether an address is an official contract of the specified type.
     * @param contractType The type of contract
     * @param contractAddress The address of the contract
     * @return isActive True if the given address is a registered and active contract of the specified type
     */
    function isActiveBalancerContract(
        ContractType contractType,
        address contractAddress
    ) external view returns (bool isActive);

    /**
     * @notice Look up a registered contract by type and name.
     * @dev This could target a particular version (e.g. `20241205-v3-weighted-pool`), or a contract alias
     * (e.g., `WeightedPool`).
     *
     * @param contractType The type of the contract
     * @param contractName The name of the contract
     * @return contractAddress The address of the associated contract, if registered, or zero
     * @return isActive True if the contract was registered and not deprecated
     */
    function getBalancerContract(
        ContractType contractType,
        string memory contractName
    ) external view returns (address contractAddress, bool isActive);

    /**
     * @notice Look up complete information about a registered contract by address.
     * @param contractAddress The address of the associated contract
     * @return info ContractInfo struct corresponding to the address
     */
    function getBalancerContractInfo(address contractAddress) external view returns (ContractInfo memory info);
}
