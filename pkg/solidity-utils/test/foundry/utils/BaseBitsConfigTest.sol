// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig, PoolConfigBits, PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

contract BaseBitsConfigTest is Test {
    using PoolConfigLib for PoolConfig;
    using PoolConfigLib for PoolConfigBits;
    using WordCodec for bytes32;

    mapping(uint256 => bool) usedBits;

    function _checkBitsUsedOnce(uint256 startBit, uint256 size) internal {
        uint256 endBit = startBit + size;
        for (uint256 i = startBit; i < endBit; i++) {
            _checkBitsUsedOnce(i);
        }
    }

    function _checkBitsUsedOnce(uint256 bitNumber) internal {
        assertEq(usedBits[bitNumber], false, "Bit already used");
        usedBits[bitNumber] = true;
    }
}
