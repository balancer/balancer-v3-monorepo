// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

import { Vault } from "./Vault.sol";
import { VaultAdmin } from "./VaultAdmin.sol";
import { VaultExtension } from "./VaultExtension.sol";
import { ProtocolFeeController } from "./ProtocolFeeController.sol";

/// @notice One-off factory to deploy the Vault at a specific address.
contract VaultFactory is Authentication {
    bytes32 public immutable vaultCreationCodeHash;
    bytes32 public immutable vaultAdminCreationCodeHash;
    bytes32 public immutable vaultExtensionCreationCodeHash;

    ProtocolFeeController public protocolFeeController;
    Vault public vault;
    VaultExtension public vaultExtension;
    VaultAdmin public vaultAdmin;

    IAuthorizer private immutable _authorizer;
    uint32 private immutable _pauseWindowDuration;
    uint32 private immutable _bufferPeriodDuration;
    uint256 private immutable _minTradeAmount;
    uint256 private immutable _minWrapAmount;
    address private immutable _deployer;

    /**
     * @notice Emitted when the Vault is deployed.
     * @param vault The Vault's address
     */
    event VaultCreated(address vault);

    error ProtocolFeeControllerNotDeployed();
    
    error VaultAdminNotDeployed();

    error WrongProtocolFeeControllerSetup(address protocolFeeControllerVault, address targetVaultAddress);

    error WrongVaultAdminSetup(address vaultAdminVault, address targetVaultAddress);

    error WrongVaultExtensionSetup(address vaultAdminVault, address targetVaultAddress);

    /// @notice The given salt does not match the generated address when attempting to create the Vault.
    error VaultAddressMismatch();

    /// @notice The bytecode for the given contract does not match the expected bytecode.
    error InvalidBytecode(string contractName);

    constructor(
        IAuthorizer authorizer,
        uint32 pauseWindowDuration,
        uint32 bufferPeriodDuration,
        uint256 minTradeAmount,
        uint256 minWrapAmount,
        bytes32 vaultCreationCodeHash_,
        bytes32 vaultExtensionCreationCodeHash_,
        bytes32 vaultAdminCreationCodeHash_
    ) Authentication(bytes32(uint256(uint160(address(this))))) {
        _deployer = msg.sender;

        vaultCreationCodeHash = vaultCreationCodeHash_;
        vaultExtensionCreationCodeHash = vaultExtensionCreationCodeHash_;
        vaultAdminCreationCodeHash = vaultAdminCreationCodeHash_;

        _authorizer = authorizer;
        _pauseWindowDuration = pauseWindowDuration;
        _bufferPeriodDuration = bufferPeriodDuration;
        _minTradeAmount = minTradeAmount;
        _minWrapAmount = minWrapAmount;
    }

    function createStage1(
        address vaultAddress,
        bytes calldata vaultAdminCreationCode
    ) external {
        protocolFeeController = new ProtocolFeeController(IVault(vaultAddress));

        if (vaultAdminCreationCodeHash != keccak256(vaultAdminCreationCode)) {
            revert InvalidBytecode("VaultAdmin");
        }

        vaultAdmin = VaultAdmin(
            payable(
                Create2.deploy(
                    0,
                    bytes32(0x00),
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


    }

    function createStage2(bytes calldata vaultExtensionCreationCode) external {
        if (vaultExtensionCreationCodeHash != keccak256(vaultExtensionCreationCode)) {
            revert InvalidBytecode("VaultExtension");
        }

        if (address(vaultAdmin) == address(0)) {
            revert VaultAdminNotDeployed();
        }

        address vaultAddress = address(vaultAdmin.vault());

        vaultExtension = VaultExtension(
            payable(
                Create2.deploy(
                    0,
                    bytes32(uint256(0x01)),
                    abi.encodePacked(vaultExtensionCreationCode, abi.encode(vaultAddress, vaultAdmin))
                )
            )
        );
    }

    /**
     * @notice Deploys the Vault.
     * @dev The Vault can only be deployed once. Therefore, this function is permissioned to ensure that it is
     * deployed to the right address.
     *
     * @param salt Salt used to create the Vault. See `getDeploymentAddress`.
     * @param targetAddress Expected Vault address. The function will revert if the given salt does not deploy the
     * Vault to the target address.
     */
    function createStage3(bytes32 salt, address targetAddress, bytes calldata vaultCreationCode) external {
        if (address(protocolFeeController) == address(0)) {
            revert ProtocolFeeControllerNotDeployed();
        }

        if (address(protocolFeeController.vault()) != targetAddress) {
            revert WrongProtocolFeeControllerSetup(address(protocolFeeController.vault()), targetAddress);
        }

        if (address(vaultAdmin.vault()) != targetAddress) {
            revert WrongVaultAdminSetup(address(vaultAdmin.vault()), targetAddress);
        }

        if (address(vaultExtension.vault()) != targetAddress) {
            revert WrongVaultExtensionSetup(address(vaultExtension.vault()), targetAddress);
        }

        if (vaultCreationCodeHash != keccak256(vaultCreationCode)) {
            revert InvalidBytecode("Vault");
        }

        address deployedAddress = CREATE3.deploy(
            salt,
            abi.encodePacked(vaultCreationCode, abi.encode(vaultExtension, _authorizer, protocolFeeController)),
            0
        );

        // We enforce the end state to match the expected outcome.
        if (deployedAddress != targetAddress) {
            revert VaultAddressMismatch();
        }

        vault = Vault(payable(deployedAddress));

        emit VaultCreated(deployedAddress);
    }

    /// @notice Gets deployment address for a given salt.
    function getDeploymentAddress(bytes32 salt) public view returns (address) {
        return CREATE3.getDeployed(salt);
    }

    function _canPerform(bytes32 actionId, address user) internal view virtual override returns (bool) {
        return _authorizer.canPerform(actionId, user, address(this));
    }
}
