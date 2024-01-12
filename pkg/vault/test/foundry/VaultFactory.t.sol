// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";

import { Vault } from "../../contracts/Vault.sol";
import { VaultExtension } from "../../contracts/VaultExtension.sol";
import { VaultFactory } from "../../contracts/VaultFactory.sol";

contract VaultFactoryTest is Test {
    address deployer;
    function setUp() public virtual {
        deployer = makeAddr("deployer");
    }

    /// forge-config: default.fuzz.runs = 100
    function testCreate(uint256 saltInt) public {
        bytes32 salt = bytes32(saltInt);

        vm.startPrank(deployer);
        IAuthorizer authorizer = new BasicAuthorizerMock();
        VaultFactory factory = new VaultFactory(authorizer, 90 days, 30 days);
        address vaultAddress = factory.getDeploymentAddress(salt);
        factory.create(salt, vaultAddress);

        // We cannot compare the deployed bytecode of the created vault against a second deployment of the vault
        // because the actionIdDisambiguator of the authentication contract is stored in immutable storage.
        // Therefore such comparison would fail, so we just call a few getters instead.
        IVault vault = IVault(vaultAddress);
        assertEq(address(vault.getAuthorizer()), address(authorizer));
        (bool isPaused, uint256 pauseWindowEndTime, uint256 bufferWindowEndTime) = vault.getVaultPausedState();
        assertEq(isPaused, false);
        assertEq(pauseWindowEndTime, block.timestamp + 90 days);
        assertEq(bufferWindowEndTime, block.timestamp + 90 days + 30 days);
    }
}
