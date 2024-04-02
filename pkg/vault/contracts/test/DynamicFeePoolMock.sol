// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { SwapLocals } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { TokenConfig, PoolData } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolMock } from "./PoolMock.sol";
import { BaseDynamicFeePool } from "../BaseDynamicFeePool.sol";

contract DynamicFeePoolMock is PoolMock, BaseDynamicFeePool {
    uint256 internal _swapFeePercentage;

    constructor(IVault vault, string memory name, string memory symbol) PoolMock(vault, name, symbol) {}

    function computeFee(PoolData memory, SwapLocals memory) public view override returns (uint256 dynamicFee) {
        return _swapFeePercentage;
    }

    function supportsInterface(bytes4 interfaceId) public view override(BaseDynamicFeePool, ERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
