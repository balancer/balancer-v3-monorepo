// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

library VaultHelpers {
    /**
     * @dev Returns the address of a Pool's contract.
     *
     * This is the same code the Vault runs in `PoolRegistry._getPoolAddress`.
     */
    function toPoolAddress(bytes32 poolId) internal pure returns (address) {
        // 12 byte logical shift left to remove the nonce and specialization setting. We don't need to mask,
        // since the logical shift already sets the upper bits to zero.
        return address(uint160(uint256(poolId)) >> (12 * 8));
    }
}
