// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtensionMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultExtensionMock.sol";

import "../VaultExtension.sol";

contract VaultExtensionMock is IVaultExtensionMock, VaultExtension {
    using PoolConfigLib for PoolConfig;

    constructor(IVault vault, IVaultAdmin vaultAdmin) VaultExtension(vault, vaultAdmin) {}

    function mockExtensionHash(bytes calldata input) external payable returns (bytes32) {
        return keccak256(input);
    }

    function manuallySetSwapFee(address pool, uint256 newSwapFee) external {
        PoolConfig memory config = _poolConfig[pool];
        config.setStaticSwapFeePercentage(newSwapFee);
        _poolConfig[pool] = config;
    }
}
