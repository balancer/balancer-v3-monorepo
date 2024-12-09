// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

import { ProtocolFeeController } from "./ProtocolFeeController.sol";
import { VaultExtension } from "./VaultExtension.sol";
import { VaultAdmin } from "./VaultAdmin.sol";

/// @notice One-off factory to deploy the Vault at a specific address.
contract VaultFactory is ReentrancyGuardTransient, Ownable2Step {
    bytes32 public immutable vaultCreationCodeHash;
    bytes32 public immutable vaultAdminCreationCodeHash;
    bytes32 public immutable vaultExtensionCreationCodeHash;

    mapping(address vaultAddress => ProtocolFeeController) public deployedProtocolFeeControllers;
    mapping(address vaultAddress => VaultExtension) public deployedVaultExtensions;
    mapping(address vaultAddress => VaultAdmin) public deployedVaultAdmins;
    mapping(address vaultAddress => bool deployed) public isDeployed;

    IAuthorizer private immutable _authorizer;
    uint32 private immutable _pauseWindowDuration;
    uint32 private immutable _bufferPeriodDuration;
    uint256 private immutable _minTradeAmount;
    uint256 private immutable _minWrapAmount;

    /**
     * @notice Emitted when the Vault is deployed.
     * @param vault The Vault's address
     */
    event VaultCreated(address vault);

    /// @notice The given salt does not match the generated address when attempting to create the Vault.
    error VaultAddressMismatch();

    /**
     * @notice The bytecode for the given contract does not match the expected bytecode.
     * @param contractName The name of the mismatched contract
     */
    error InvalidBytecode(string contractName);

    /**
     * @notice The Vault has already been deployed at this target address.
     * @param vault Vault address already consumed by a previous deployment
     */
    error VaultAlreadyDeployed(address vault);

    constructor(
        IAuthorizer authorizer,
        uint32 pauseWindowDuration,
        uint32 bufferPeriodDuration,
        uint256 minTradeAmount,
        uint256 minWrapAmount,
        bytes32 vaultCreationCodeHash_,
        bytes32 vaultExtensionCreationCodeHash_,
        bytes32 vaultAdminCreationCodeHash_
    ) Ownable(msg.sender) {
        vaultCreationCodeHash = vaultCreationCodeHash_;
        vaultAdminCreationCodeHash = vaultAdminCreationCodeHash_;
        vaultExtensionCreationCodeHash = vaultExtensionCreationCodeHash_;

        _authorizer = authorizer;
        _pauseWindowDuration = pauseWindowDuration;
        _bufferPeriodDuration = bufferPeriodDuration;
        _minTradeAmount = minTradeAmount;
        _minWrapAmount = minWrapAmount;
    }

    /**
     * @notice Deploys the Vault.
     * @dev The Vault can only be deployed once per salt. This function is permissioned.
     *
     * @param salt Salt used to create the Vault. See `getDeploymentAddress`
     * @param targetAddress Expected Vault address. The function will revert if the given salt does not deploy the
     * Vault to the target address
     * @param vaultCreationCode Creation code for the Vault
     * @param vaultExtensionCreationCode Creation code for the VaultExtension
     * @param vaultAdminCreationCode Creation code for the VaultAdmin
     */
    function create(
        bytes32 salt,
        address targetAddress,
        bytes calldata vaultCreationCode,
        bytes calldata vaultExtensionCreationCode,
        bytes calldata vaultAdminCreationCode
    ) external onlyOwner nonReentrant {
        if (isDeployed[targetAddress]) {
            revert VaultAlreadyDeployed(targetAddress);
        }

        if (vaultCreationCodeHash != keccak256(vaultCreationCode)) {
            revert InvalidBytecode("Vault");
        } else if (vaultAdminCreationCodeHash != keccak256(vaultAdminCreationCode)) {
            revert InvalidBytecode("VaultAdmin");
        } else if (vaultExtensionCreationCodeHash != keccak256(vaultExtensionCreationCode)) {
            revert InvalidBytecode("VaultExtension");
        }

        address vaultAddress = getDeploymentAddress(salt);
        if (targetAddress != vaultAddress) {
            revert VaultAddressMismatch();
        }

        ProtocolFeeController protocolFeeController = new ProtocolFeeController(IVault(vaultAddress));
        deployedProtocolFeeControllers[vaultAddress] = protocolFeeController;

        VaultAdmin vaultAdmin = VaultAdmin(
            payable(
                Create2.deploy(
                    0, // ETH value
                    salt,
                    abi.encodePacked(
                        vaultAdminCreationCode,
                        abi.encode(
                            IVault(vaultAddress),
                            _pauseWindowDuration,
                            _bufferPeriodDuration,
                            _minTradeAmount,
                            _minWrapAmount
                        )
                    )
                )
            )
        );
        deployedVaultAdmins[vaultAddress] = vaultAdmin;

        VaultExtension vaultExtension = VaultExtension(
            payable(
                Create2.deploy(
                    0, // ETH value
                    salt,
                    abi.encodePacked(vaultExtensionCreationCode, abi.encode(vaultAddress, vaultAdmin))
                )
            )
        );
        deployedVaultExtensions[vaultAddress] = vaultExtension;

        address deployedAddress = CREATE3.deploy(
            salt,
            abi.encodePacked(vaultCreationCode, abi.encode(vaultExtension, _authorizer, protocolFeeController)),
            0
        );

        // This should always be the case, but we enforce the end state to match the expected outcome anyway.
        if (deployedAddress != vaultAddress) {
            revert VaultAddressMismatch();
        }

        emit VaultCreated(vaultAddress);

        isDeployed[vaultAddress] = true;
    }

    /// @notice Gets deployment address for a given salt.
    function getDeploymentAddress(bytes32 salt) public view returns (address) {
        return CREATE3.getDeployed(salt);
    }
}
