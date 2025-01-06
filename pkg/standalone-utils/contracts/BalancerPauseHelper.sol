// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { Enum, Safe } from "@safe-global/safe-contracts/contracts/Safe.sol";

contract BalancerPauseHelper is SingletonAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;

    error AddressIsNotContract(address contractAddress);
    error AddressIsZero();

    event PoolAdded(address pool);
    event PoolDeleted(address pool);

    Safe public immutable safe;

    EnumerableSet.AddressSet private poolsSet;

    constructor(IVault vault, Safe safe_) SingletonAuthentication(vault) {
        _expectContract(address(safe_));

        safe = safe_;
    }

    // --------------------------  Setup Pools --------------------------
    function addPools(address[] calldata newPools) external authenticate {
        uint256 length = newPools.length;

        for (uint256 i = 0; i < length; i++) {
            _expectContract(newPools[i]);
            poolsSet.add(newPools[i]);

            emit PoolAdded(newPools[i]);
        }
    }

    function removePool(uint256 index) external authenticate {
        uint256 poolsSetLength = poolsSet.length();
        require(index < poolsSetLength, "Index out of bounds");

        address[] memory pools = new address[](1);
        pools[0] = poolsSet.at(index);
        removePools(pools);
    }

    function removePools(address[] memory pools) public authenticate {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            poolsSet.remove(pools[i]);

            emit PoolDeleted(pools[i]);
        }
    }

    // --------------------------  Pause Pools --------------------------

    function pause(uint256 from, uint256 to) external authenticate {
        pause(getPools(from, to));
    }

    function pause(uint256[] calldata poolsIndexes) external authenticate {
        pause(getPools(poolsIndexes));
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

    function getPool(uint256 index) external view returns (address) {
        require(index < poolsSet.length(), "Index out of bounds");
        return poolsSet.at(index);
    }

    function getPools(uint256[] calldata poolsIndexes) public view returns (address[] memory pools) {
        uint256 length = poolsIndexes.length;
        pools = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            uint256 poolIndex = poolsIndexes[i];
            require(poolIndex < length, "Index out of bounds");

            pools[i] = poolsSet.at(poolIndex);
        }
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

    // --------------------------  Private functions --------------------------

    function _expectContract(address contractAddress) private view {
        if (contractAddress == address(0)) {
            revert AddressIsZero();
        } else if (contractAddress.code.length == 0) {
            revert AddressIsNotContract(contractAddress);
        }
    }
}
