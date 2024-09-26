// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ProtocolFeeControllerMock } from "../../../contracts/test/ProtocolFeeControllerMock.sol";
import { BasicAuthorizerMock } from "../../../contracts/test/BasicAuthorizerMock.sol";
import { ProtocolFeeController } from "../../../contracts/ProtocolFeeController.sol";
import { VaultExtensionMock } from "../../../contracts/test/VaultExtensionMock.sol";
import { VaultAdminMock } from "../../../contracts/test/VaultAdminMock.sol";
import { VaultMock } from "../../../contracts/test/VaultMock.sol";

library VaultMockDeployer {
    function deploy() internal returns (VaultMock vault) {
        return deploy(0, 0);
    }

    function deploy(uint256 minTradeAmount, uint256 minWrapAmount) internal returns (VaultMock vault) {
        IAuthorizer authorizer = new BasicAuthorizerMock();
        bytes32 salt = bytes32(0);
        vault = VaultMock(payable(CREATE3.getDeployed(salt)));
        VaultAdminMock vaultAdmin = new VaultAdminMock(
            IVault(address(vault)),
            90 days,
            30 days,
            minTradeAmount,
            minWrapAmount
        );
        VaultExtensionMock vaultExtension = new VaultExtensionMock(IVault(address(vault)), vaultAdmin);
        ProtocolFeeController protocolFeeController = new ProtocolFeeControllerMock(IVault(address(vault)));

        _create(abi.encode(vaultExtension, authorizer, protocolFeeController), salt);
        return vault;
    }

    function _create(bytes memory constructorArgs, bytes32 salt) internal returns (address) {
        return CREATE3.deploy(salt, abi.encodePacked(type(VaultMock).creationCode, constructorArgs), 0);
    }
}
