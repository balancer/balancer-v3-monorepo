// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

import { VaultAdmin } from "./VaultAdmin.sol";
import { VaultExtension } from "./VaultExtension.sol";
import { ProtocolFeeController } from "./ProtocolFeeController.sol";

/// @notice One-off factory to deploy the Vault at a specific address.
contract VaultFactory is Authentication {
    bytes32 public immutable vaultCreationCodeHash;
    bytes32 public immutable vaultAdminCreationCodeHash;
    bytes32 public immutable vaultExtensionCreationCodeHash;

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
        bytes32 vaultAdminCreationCodeHash_,
        bytes32 vaultExtensionCreationCodeHash_
    ) Authentication(bytes32(uint256(uint160(address(this))))) {
        _deployer = msg.sender;

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
        bytes calldata vaultAdminCreationCode,
        bytes calldata vaultExtensionCreationCode
    ) external authenticate {
        if (vaultCreationCodeHash != keccak256(vaultCreationCode)) {
            revert InvalidBytecode("Vault");
        } else if (vaultAdminCreationCodeHash != keccak256(vaultAdminCreationCode)) {
            revert InvalidBytecode("VaultAdmin");
        } else if (vaultExtensionCreationCodeHash != keccak256(vaultExtensionCreationCode)) {
            revert InvalidBytecode("VaultExtension");
        }

        address vaultAddress = getDeploymentAddress(msg.sender, salt);
        if (targetAddress != vaultAddress) {
            revert VaultAddressMismatch();
        }

        ProtocolFeeController feeController = new ProtocolFeeController(IVault(vaultAddress));

        VaultAdmin vaultAdmin = VaultAdmin(
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

        VaultExtension vaultExtension = VaultExtension(
            payable(
                Create2.deploy(
                    0,
                    bytes32(uint256(0x01)),
                    abi.encodePacked(vaultExtensionCreationCode, abi.encode(vaultAddress, vaultAdmin))
                )
            )
        );

        salt = keccak256(abi.encodePacked(msg.sender, salt));
        address deployedAddress = CREATE3.deploy(
            salt,
            abi.encodePacked(vaultCreationCode, abi.encode(vaultExtension, _authorizer, feeController)),
            0
        );

        // This should always be the case, but we enforce the end state to match the expected outcome anyway.
        if (deployedAddress != vaultAddress) {
            revert VaultAddressMismatch();
        }

        emit VaultCreated(vaultAddress);
    }

    /// @notice Gets deployment address for a given caller and salt.
    function getDeploymentAddress(address caller, bytes32 salt) public view returns (address) {
        salt = keccak256(abi.encodePacked(caller, salt));
        return CREATE3.getDeployed(salt);
    }

    function _canPerform(bytes32 actionId, address user) internal view virtual override returns (bool) {
        return _authorizer.canPerform(actionId, user, address(this));
    }
}
