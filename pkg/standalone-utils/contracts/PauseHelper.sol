// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { Enum, Safe } from "@safe-global/safe-contracts/contracts/Safe.sol";

contract PauseHelper is SingletonAuthentication {
    // TODO: Add comments
    using EnumerableSet for EnumerableSet.AddressSet;

    event PoolAdded(address pool);
    event PoolRemoved(address pool);

    Safe public immutable safe;

    EnumerableSet.AddressSet private poolsSet;

    constructor(IVault vault, Safe safe_) SingletonAuthentication(vault) {
        safe = safe_;
    }

    // --------------------------  Manage Pools --------------------------
    function addPools(address[] calldata newPools) external authenticate {
        uint256 length = newPools.length;

        for (uint256 i = 0; i < length; i++) {
            poolsSet.add(newPools[i]);

            emit PoolAdded(newPools[i]);
        }
    }

    function removePools(address[] memory pools) public authenticate {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            poolsSet.remove(pools[i]);

            emit PoolRemoved(pools[i]);
        }
    }

    function pause(address[] memory pools) public authenticate {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            safe.execTransactionFromModule(
                address(getVault()),
                0,
                abi.encodeWithSelector(IVaultAdmin.pausePool.selector, pools[i]),
                Enum.Operation.Call
            );
        }
    }

    // --------------------------  Getters --------------------------
    function getPoolsCount() external view returns (uint256) {
        return poolsSet.length();
    }

    function hasPool(address pool) external view returns (bool) {
        return poolsSet.contains(pool);
    }

    function getPools(uint256 from, uint256 to) public view returns (address[] memory pools) {
        uint256 poolLength = poolsSet.length();
        require(from <= to, "'From' must be less than 'to'");
        require(to <= poolLength, "'To' must be less than or eq the number of pools");
        require(from < poolLength, "'From' must be less than the number of pools");

        pools = new address[](to - from);
        for (uint256 i = from; i < to; i++) {
            pools[i - from] = poolsSet.at(i);
        }
    }
}
