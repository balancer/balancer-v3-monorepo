// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { HooksConfigLib } from "@balancer-labs/v3-vault/contracts/lib/HooksConfigLib.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { BaseBitsConfigTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseBitsConfigTest.sol";

contract HooksConfigLibTest is BaseBitsConfigTest {
    using WordCodec for bytes32;
    using HooksConfigLib for HooksConfigBits;
    using ArrayHelpers for *;

    uint256 public constant ADDRESS_BITLENGTH = 160;

    uint256 public staticSwapFeePercentage = 5e18;
    address public hooksContract = address(0x05);

    function testOffsets() public {
        _checkBitsUsedOnce(HooksConfigLib.BEFORE_INITIALIZE_OFFSET);
        _checkBitsUsedOnce(HooksConfigLib.AFTER_INITIALIZE_OFFSET);
        _checkBitsUsedOnce(HooksConfigLib.DYNAMIC_SWAP_FEE_OFFSET);
        _checkBitsUsedOnce(HooksConfigLib.BEFORE_SWAP_OFFSET);
        _checkBitsUsedOnce(HooksConfigLib.AFTER_SWAP_OFFSET);
        _checkBitsUsedOnce(HooksConfigLib.BEFORE_ADD_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(HooksConfigLib.AFTER_ADD_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(HooksConfigLib.BEFORE_REMOVE_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(HooksConfigLib.AFTER_REMOVE_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(HooksConfigLib.HOOKS_CONTRACT_OFFSET, ADDRESS_BITLENGTH);
    }

    function testZeroConfigBytes() public {
        HooksConfigBits memory config;

        assertFalse(config.shouldCallBeforeInitialize(), "shouldCallBeforeInitialize should be false");
        assertFalse(config.shouldCallAfterInitialize(), "shouldCallAfterInitialize should be false");
        assertFalse(config.shouldCallComputeDynamicSwapFee(), "shouldCallComputeDynamicSwapFee should be false");
        assertFalse(config.shouldCallBeforeSwap(), "shouldCallBeforeSwap should be false");
        assertFalse(config.shouldCallAfterSwap(), "shouldCallAfterSwap should be false");
        assertFalse(config.shouldCallBeforeAddLiquidity(), "shouldCallBeforeAddLiquidity should be false");
        assertFalse(config.shouldCallAfterAddLiquidity(), "shouldCallAfterAddLiquidity should be false");
        assertFalse(config.shouldCallBeforeRemoveLiquidity(), "shouldCallBeforeRemoveLiquidity should be false");
        assertFalse(config.shouldCallAfterRemoveLiquidity(), "shouldCallAfterRemoveLiquidity should be false");
        assertEq(config.getHooksContract(), address(0), "getHooksContract should be address(0)");
    }

    // #region test setters and getters
    function testShouldCallBeforeInitialize() public {
        HooksConfigBits memory config;
        config.bits = config.bits.insertBool(true, HooksConfigLib.BEFORE_INITIALIZE_OFFSET);
        assertEq(config.shouldCallBeforeInitialize(), true, "shouldCallBeforeInitialize should be true");
    }

    function testSetShouldCallBeforeInitialize() public {
        HooksConfigBits memory config;
        HooksConfigLib.setShouldCallBeforeInitialize(config, true);
        assertEq(config.shouldCallBeforeInitialize(), true, "shouldCallBeforeInitialize should be true");
    }

    function testShouldCallAfterInitialize() public {
        HooksConfigBits memory config;
        config.bits = config.bits.insertBool(true, HooksConfigLib.AFTER_INITIALIZE_OFFSET);
        assertEq(config.shouldCallAfterInitialize(), true, "shouldCallAfterInitialize should be true");
    }

    function testSetShouldCallAfterInitialize() public {
        HooksConfigBits memory config;
        HooksConfigLib.setShouldCallAfterInitialize(config, true);
        assertEq(config.shouldCallAfterInitialize(), true, "shouldCallAfterInitialize should be true");
    }

    function testShouldCallComputeDynamicSwapFee() public {
        HooksConfigBits memory config;
        config.bits = config.bits.insertBool(true, HooksConfigLib.DYNAMIC_SWAP_FEE_OFFSET);
        assertEq(config.shouldCallComputeDynamicSwapFee(), true, "shouldCallComputeDynamicSwapFee should be true");
    }

    function testSetShouldCallComputeDynamicSwapFee() public {
        HooksConfigBits memory config;
        HooksConfigLib.setShouldCallComputeDynamicSwapFee(config, true);
        assertEq(config.shouldCallComputeDynamicSwapFee(), true, "shouldCallComputeDynamicSwapFee should be true");
    }

    function testShouldCallBeforeSwap() public {
        HooksConfigBits memory config;
        config.bits = config.bits.insertBool(true, HooksConfigLib.BEFORE_SWAP_OFFSET);
        assertEq(config.shouldCallBeforeSwap(), true, "shouldCallBeforeSwap should be true");
    }

    function testSetShouldCallBeforeSwap() public {
        HooksConfigBits memory config;
        HooksConfigLib.setShouldCallBeforeSwap(config, true);
        assertEq(config.shouldCallBeforeSwap(), true, "shouldCallBeforeSwap should be true");
    }

    function testShouldCallAfterSwap() public {
        HooksConfigBits memory config;
        config.bits = config.bits.insertBool(true, HooksConfigLib.AFTER_SWAP_OFFSET);
        assertEq(config.shouldCallAfterSwap(), true, "shouldCallAfterSwap should be true");
    }

    function testSetShouldCallAfterSwap() public {
        HooksConfigBits memory config;
        HooksConfigLib.setShouldCallAfterSwap(config, true);
        assertEq(config.shouldCallAfterSwap(), true, "shouldCallAfterSwap should be true");
    }

    function testShouldCallBeforeAddLiquidity() public {
        HooksConfigBits memory config;
        config.bits = config.bits.insertBool(true, HooksConfigLib.BEFORE_ADD_LIQUIDITY_OFFSET);
        assertEq(config.shouldCallBeforeAddLiquidity(), true, "shouldCallBeforeAddLiquidity should be true");
    }

    function testSetShouldCallBeforeAddLiquidity() public {
        HooksConfigBits memory config;
        HooksConfigLib.setShouldCallBeforeAddLiquidity(config, true);
        assertEq(config.shouldCallBeforeAddLiquidity(), true, "shouldCallBeforeAddLiquidity should be true");
    }

    function testShouldCallAfterAddLiquidity() public {
        HooksConfigBits memory config;
        config.bits = config.bits.insertBool(true, HooksConfigLib.AFTER_ADD_LIQUIDITY_OFFSET);
        assertEq(config.shouldCallAfterAddLiquidity(), true, "shouldCallAfterAddLiquidity should be true");
    }

    function testSetShouldCallAfterAddLiquidity() public {
        HooksConfigBits memory config;
        HooksConfigLib.setShouldCallAfterAddLiquidity(config, true);
        assertEq(config.shouldCallAfterAddLiquidity(), true, "shouldCallAfterAddLiquidity should be true");
    }

    function testShouldCallBeforeRemoveLiquidity() public {
        HooksConfigBits memory config;
        config.bits = config.bits.insertBool(true, HooksConfigLib.BEFORE_REMOVE_LIQUIDITY_OFFSET);
        assertEq(config.shouldCallBeforeRemoveLiquidity(), true, "shouldCallBeforeRemoveLiquidity should be true");
    }

    function testSetShouldCallBeforeRemoveLiquidity() public {
        HooksConfigBits memory config;
        HooksConfigLib.setShouldCallBeforeRemoveLiquidity(config, true);
        assertEq(config.shouldCallBeforeRemoveLiquidity(), true, "shouldCallBeforeRemoveLiquidity should be true");
    }

    function testShouldCallAfterRemoveLiquidity() public {
        HooksConfigBits memory config;
        config.bits = config.bits.insertBool(true, HooksConfigLib.AFTER_REMOVE_LIQUIDITY_OFFSET);
        assertEq(config.shouldCallAfterRemoveLiquidity(), true, "shouldCallAfterRemoveLiquidity should be true");
    }

    function testSetShouldCallAfterRemoveLiquidity() public {
        HooksConfigBits memory config;
        HooksConfigLib.setShouldCallAfterRemoveLiquidity(config, true);
        assertEq(config.shouldCallAfterRemoveLiquidity(), true, "shouldCallAfterRemoveLiquidity should be true");
    }

    function testGetHooksContract() public {
        HooksConfigBits memory config;
        config.bits = config.bits.insertAddress(hooksContract, HooksConfigLib.HOOKS_CONTRACT_OFFSET);
        assertEq(config.getHooksContract(), hooksContract, "getHooksContract should be hooksContract");
    }

    function testSetHooksContract() public {
        HooksConfigBits memory config;
        HooksConfigLib.setHooksContract(config, hooksContract);
        assertEq(config.getHooksContract(), hooksContract, "getHooksContract should be hooksContract");
    }
    // #endregion
}
