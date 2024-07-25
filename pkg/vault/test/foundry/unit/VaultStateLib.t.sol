// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { BaseBitsConfigTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseBitsConfigTest.sol";

import { VaultStateLib, VaultStateBits, VaultStateBits } from "../../../contracts/lib/VaultStateLib.sol";

contract VaultStateLibTest is BaseBitsConfigTest {
    using VaultStateLib for VaultStateBits;
    using WordCodec for bytes32;

    function testOffsets() public {
        _checkBitsUsedOnce(VaultStateLib.QUERY_DISABLED_OFFSET);
        _checkBitsUsedOnce(VaultStateLib.VAULT_PAUSED_OFFSET);
        _checkBitsUsedOnce(VaultStateLib.BUFFER_PAUSED_OFFSET);
    }

    function testZeroConfigBytes() public pure {
        VaultStateBits state;

        assertFalse(state.isQueryDisabled(), "isQueryDisabled should be false");
        assertFalse(state.isVaultPaused(), "isVaultPaused should be false");
        assertFalse(state.areBuffersPaused(), "areBuffersPaused should be false");
    }

    function testIsQueryDisabled() public pure {
        VaultStateBits state;
        state = VaultStateBits.wrap(VaultStateBits.unwrap(state).insertBool(true, VaultStateLib.QUERY_DISABLED_OFFSET));
        assertTrue(state.isQueryDisabled(), "isQueryDisabled should be true");
    }

    function testSetQueryDisabled() public pure {
        VaultStateBits state;
        state = state.setQueryDisabled(true);
        assertTrue(state.isQueryDisabled(), "isQueryDisabled should be true");
    }

    function testIsVaultPaused() public pure {
        VaultStateBits state;
        state = VaultStateBits.wrap(VaultStateBits.unwrap(state).insertBool(true, VaultStateLib.VAULT_PAUSED_OFFSET));
        assertTrue(state.isVaultPaused(), "isVaultPaused should be true");
    }

    function testSetVaultPaused() public pure {
        VaultStateBits state;
        state = state.setVaultPaused(true);
        assertTrue(state.isVaultPaused(), "isVaultPaused should be true");
    }

    function testAreBuffersPaused() public pure {
        VaultStateBits state;
        state = VaultStateBits.wrap(VaultStateBits.unwrap(state).insertBool(true, VaultStateLib.BUFFER_PAUSED_OFFSET));
        assertTrue(state.areBuffersPaused(), "areBuffersPaused should be true");
    }

    function testSetBuffersPaused() public pure {
        VaultStateBits state;
        state = state.setBuffersPaused(true);
        assertTrue(state.areBuffersPaused(), "areBuffersPaused should be true");
    }
}
