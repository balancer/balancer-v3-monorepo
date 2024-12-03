// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BasicAuthorizerMock } from "../../contracts/test/BasicAuthorizerMock.sol";
import { VaultFactory } from "../../contracts/VaultFactory.sol";
import { VaultContractsDeployer } from "./utils/VaultContractsDeployer.sol";
import { Vault } from "../../contracts/Vault.sol";
import { VaultAdmin } from "../../contracts/VaultAdmin.sol";
import { VaultExtension } from "../../contracts/VaultExtension.sol";

contract VaultFactoryTest is Test, VaultContractsDeployer {
    // Should match the "PRODUCTION" limits in BaseVaultTest.
    uint256 private constant _MIN_TRADE_AMOUNT = 1e6;
    uint256 private constant _MIN_WRAP_AMOUNT = 1e4;

    address deployer;
    address other;
    BasicAuthorizerMock authorizer;
    VaultFactory factory;

    function setUp() public virtual {
        deployer = makeAddr("deployer");
        other = makeAddr("other");
        authorizer = deployBasicAuthorizerMock();
        vm.startPrank(deployer);
        factory = deployVaultFactory(
            authorizer,
            90 days,
            30 days,
            _MIN_TRADE_AMOUNT,
            _MIN_WRAP_AMOUNT,
            keccak256(type(Vault).creationCode),
            keccak256(type(VaultExtension).creationCode),
            keccak256(type(VaultAdmin).creationCode)
        );
        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 100
    function testCreateVault__Fuzz(bytes32 salt) public {
        address vaultAddress = factory.getDeploymentAddress(salt);

        assertFalse(factory.isDeployed(vaultAddress), "Deployment flag is set before deployment");

        vm.prank(deployer);
        factory.create(
            salt,
            vaultAddress,
            type(Vault).creationCode,
            type(VaultExtension).creationCode,
            type(VaultAdmin).creationCode
        );

        assertTrue(factory.isDeployed(vaultAddress), "Deployment flag not set for the vault address");
        assertNotEq(
            address(factory.deployedProtocolFeeControllers(vaultAddress)),
            address(0),
            "Protocol fee controller not set for vault address"
        );
        assertNotEq(
            address(factory.deployedVaultExtensions(vaultAddress)),
            address(0),
            "Vault extension not set for vault address"
        );
        assertNotEq(
            address(factory.deployedVaultAdmins(vaultAddress)),
            address(0),
            "Vault admin not set for vault address"
        );

        // We cannot compare the deployed bytecode of the created vault against a second deployment of the Vault
        // because the actionIdDisambiguator of the authentication contract is stored in immutable storage.
        // Therefore such comparison would fail, so we just call a few getters instead.
        IVault vault = IVault(vaultAddress);
        assertEq(address(vault.getAuthorizer()), address(authorizer));

        (bool isPaused, uint32 pauseWindowEndTime, uint32 bufferWindowEndTime) = vault.getVaultPausedState();
        assertEq(isPaused, false);
        assertEq(pauseWindowEndTime, block.timestamp + 90 days, "Wrong pause window end time");
        assertEq(bufferWindowEndTime, block.timestamp + 90 days + 30 days, "Wrong buffer window end time");
    }

    function testCreateNotAuthorized() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
        factory.create(
            bytes32(0),
            address(0),
            type(Vault).creationCode,
            type(VaultExtension).creationCode,
            type(VaultAdmin).creationCode
        );
    }

    function testCreateMismatch() public {
        bytes32 salt = bytes32(uint256(123));

        address vaultAddress = factory.getDeploymentAddress(salt);
        vm.prank(deployer);
        vm.expectRevert(VaultFactory.VaultAddressMismatch.selector);
        factory.create(
            bytes32(uint256(salt) + 1),
            vaultAddress,
            type(Vault).creationCode,
            type(VaultExtension).creationCode,
            type(VaultAdmin).creationCode
        );
    }

    function testCreateTwice() public {
        bytes32 salt = bytes32(uint256(123));
        address vaultAddress = factory.getDeploymentAddress(salt);

        vm.startPrank(deployer);
        factory.create(
            salt,
            vaultAddress,
            type(Vault).creationCode,
            type(VaultExtension).creationCode,
            type(VaultAdmin).creationCode
        );

        // Can't deploy to the same address twice.
        vm.expectRevert(abi.encodeWithSelector(VaultFactory.VaultAlreadyDeployed.selector, vaultAddress));
        factory.create(
            salt,
            vaultAddress,
            type(Vault).creationCode,
            type(VaultExtension).creationCode,
            type(VaultAdmin).creationCode
        );

        // Can deploy to a different address using a different salt.
        bytes32 salt2 = bytes32(uint256(321));
        address vaultAddress2 = factory.getDeploymentAddress(salt2);

        factory.create(
            salt2,
            vaultAddress2,
            type(Vault).creationCode,
            type(VaultExtension).creationCode,
            type(VaultAdmin).creationCode
        );
    }

    function testInvalidVaultBytecode() public {
        bytes32 salt = bytes32(uint256(123));

        address vaultAddress = factory.getDeploymentAddress(salt);
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(VaultFactory.InvalidBytecode.selector, "Vault"));
        factory.create(
            salt,
            vaultAddress,
            new bytes(0),
            type(VaultExtension).creationCode,
            type(VaultAdmin).creationCode
        );
    }

    function testInvalidVaultAdminBytecode() public {
        bytes32 salt = bytes32(uint256(123));

        address vaultAddress = factory.getDeploymentAddress(salt);
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(VaultFactory.InvalidBytecode.selector, "VaultAdmin"));
        factory.create(salt, vaultAddress, type(Vault).creationCode, type(VaultExtension).creationCode, new bytes(0));
    }

    function testInvalidVaultExtensionBytecode() public {
        bytes32 salt = bytes32(uint256(123));

        address vaultAddress = factory.getDeploymentAddress(salt);
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(VaultFactory.InvalidBytecode.selector, "VaultExtension"));
        factory.create(salt, vaultAddress, type(Vault).creationCode, new bytes(0), type(VaultAdmin).creationCode);
    }
}
