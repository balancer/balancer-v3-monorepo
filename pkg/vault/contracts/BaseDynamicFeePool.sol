// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { IBaseDynamicFeePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBaseDynamicFeePool.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { PoolData } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { SwapLocals } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";

import { BalancerPoolToken } from "./BalancerPoolToken.sol";

abstract contract BaseDynamicFeePool is IBasePool, IBaseDynamicFeePool, BalancerPoolToken {
    function computeFee(PoolData memory poolData, SwapLocals memory vars) public view virtual returns (uint256);

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IBaseDynamicFeePool).interfaceId || super.supportsInterface(interfaceId);
    }
}
