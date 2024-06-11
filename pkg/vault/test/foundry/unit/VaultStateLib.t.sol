// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { VaultState, VaultStateBits } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { VaultStateLib } from "@balancer-labs/v3-vault/contracts/lib/VaultStateLib.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

import { BaseBitsConfigTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseBitsConfigTest.sol";

contract VaultStateLibTest is BaseBitsConfigTest {
    using WordCodec for bytes32;
    using VaultStateLib for VaultStateBits;

    function testOffsets() public {
        _checkBitsUsedOnce(VaultStateLib.QUERY_DISABLED_OFFSET);
        _checkBitsUsedOnce(VaultStateLib.VAULT_PAUSED_OFFSET);
        _checkBitsUsedOnce(VaultStateLib.BUFFER_PAUSED_OFFSET);
    }

    function testZeroConfigBytes() public {
        VaultStateBits memory state;

        assertFalse(state.isQueryDisabled(), "isQueryDisabled should be false");
        assertFalse(state.isVaultPaused(), "isVaultPaused should be false");
        assertFalse(state.areBuffersPaused(), "areBuffersPaused should be false");
    }

    function testIsQueryDisabled() public {
        VaultStateBits memory state;
        state.bits = state.bits.insertBool(true, VaultStateLib.QUERY_DISABLED_OFFSET);
        assertEq(VaultStateLib.isQueryDisabled(state), true, "isQueryDisabled should be true");
    }

    function testSetQueryDisabled() public {
        VaultStateBits memory state;
        VaultStateLib.setQueryDisabled(state, true);
        assertEq(VaultStateLib.isQueryDisabled(state), true, "isQueryDisabled should be true");
    }

    function testIsVaultPaused() public {
        VaultStateBits memory state;
        state.bits = state.bits.insertBool(true, VaultStateLib.VAULT_PAUSED_OFFSET);
        assertEq(VaultStateLib.isVaultPaused(state), true, "isVaultPaused should be true");
    }

    function testSetVaultPaused() public {
        VaultStateBits memory state;
        VaultStateLib.setVaultPaused(state, true);
        assertEq(VaultStateLib.isVaultPaused(state), true, "isVaultPaused should be true");
    }

    function testAreBuffersPaused() public {
        VaultStateBits memory state;
        state.bits = state.bits.insertBool(true, VaultStateLib.BUFFER_PAUSED_OFFSET);
        assertEq(VaultStateLib.areBuffersPaused(state), true, "areBuffersPaused should be true");
    }

    function testSetBuffersPaused() public {
        VaultStateBits memory state;
        VaultStateLib.setBuffersPaused(state, true);
        assertEq(VaultStateLib.areBuffersPaused(state), true, "areBuffersPaused should be true");
    }
}
