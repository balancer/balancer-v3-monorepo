// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

import { VaultAdmin } from "./VaultAdmin.sol";
import { VaultExtension } from "./VaultExtension.sol";
import { ProtocolFeeController } from "./ProtocolFeeController.sol";

/// @notice One-off factory to deploy the Vault at a specific address.
contract VaultFactory is Ownable2Step {
    bytes32 public immutable vaultCreationCodeHash;
    bytes32 public immutable vaultAdminCreationCodeHash;
    bytes32 public immutable vaultExtensionCreationCodeHash;

    ProtocolFeeController public protocolFeeController;
    VaultExtension public vaultExtension;
    VaultAdmin public vaultAdmin;

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
     * @dev The Vault can only be deployed once. Therefore, this function is permissioned to ensure that it is
     * deployed to the right address.
     *
     * @param salt Salt used to create the Vault. See `getDeploymentAddress`.
     * @param targetAddress Expected Vault address. The function will revert if the given salt does not deploy the
     * Vault to the target address.
     */
    function create(
        bytes32 salt,
        address targetAddress,
        bytes calldata vaultCreationCode,
        bytes calldata vaultExtensionCreationCode,
        bytes calldata vaultAdminCreationCode
    ) external onlyOwner {
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

        protocolFeeController = new ProtocolFeeController(IVault(vaultAddress));

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

        vaultExtension = VaultExtension(
            payable(
                Create2.deploy(
                    0,
                    bytes32(uint256(0x01)),
                    abi.encodePacked(vaultExtensionCreationCode, abi.encode(vaultAddress, vaultAdmin))
                )
            )
        );

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
    }

    /// @notice Gets deployment address for a given salt.
    function getDeploymentAddress(bytes32 salt) public view returns (address) {
        return CREATE3.getDeployed(salt);
    }
}
