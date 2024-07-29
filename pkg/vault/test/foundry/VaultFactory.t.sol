// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";

import { VaultFactory } from "../../contracts/VaultFactory.sol";

contract VaultFactoryTest is Test {
    address deployer;
    BasicAuthorizerMock authorizer;
    VaultFactory factory;

    function setUp() public virtual {
        deployer = makeAddr("deployer");
        authorizer = new BasicAuthorizerMock();
        factory = new VaultFactory(authorizer, 90 days, 30 days);
    }

    /// forge-config: default.fuzz.runs = 100
    function testCreateVault__Fuzz(bytes32 salt) public {
        authorizer.grantRole(factory.getActionId(VaultFactory.create.selector), deployer);

        address vaultAddress = factory.getDeploymentAddress(salt);
        vm.prank(deployer);
        factory.create(salt, vaultAddress);

        // We cannot compare the deployed bytecode of the created vault against a second deployment of the vault
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
        vm.prank(deployer);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        factory.create(bytes32(0), address(0));
    }

    function testCreateMismatch() public {
        bytes32 salt = bytes32(uint256(123));
        authorizer.grantRole(factory.getActionId(VaultFactory.create.selector), deployer);

        address vaultAddress = factory.getDeploymentAddress(salt);
        vm.prank(deployer);
        vm.expectRevert(VaultFactory.VaultAddressMismatch.selector);
        factory.create(bytes32(uint256(salt) + 1), vaultAddress);
    }

    function testCreateTwice() public {
        bytes32 salt = bytes32(uint256(123));
        authorizer.grantRole(factory.getActionId(VaultFactory.create.selector), deployer);

        address vaultAddress = factory.getDeploymentAddress(salt);
        vm.startPrank(deployer);
        factory.create(salt, vaultAddress);
        vm.expectRevert(VaultFactory.VaultAlreadyCreated.selector);
        factory.create(salt, vaultAddress);
    }
}
