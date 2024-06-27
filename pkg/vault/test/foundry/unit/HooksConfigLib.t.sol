// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BaseBitsConfigTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseBitsConfigTest.sol";

import { HooksConfigLib, HooksConfigBits } from "../../../contracts/lib/HooksConfigLib.sol";

contract HooksConfigLibTest is BaseBitsConfigTest {
    using WordCodec for bytes32;
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

    function testZeroConfigBytes() public pure {
        HooksConfigBits config;

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
    function testShouldCallBeforeInitialize() public pure {
        HooksConfigBits config;
        config = HooksConfigBits.wrap(
            HooksConfigBits.unwrap(config).insertBool(true, HooksConfigLib.BEFORE_INITIALIZE_OFFSET)
        );
        assertEq(config.shouldCallBeforeInitialize(), true, "shouldCallBeforeInitialize should be true (getter)");
    }

    function testSetShouldCallBeforeInitialize() public pure {
        HooksConfigBits config;
        config = config.setShouldCallBeforeInitialize(true);
        assertEq(config.shouldCallBeforeInitialize(), true, "shouldCallBeforeInitialize should be true (setter)");
    }

    function testShouldCallAfterInitialize() public pure {
        HooksConfigBits config;
        config = HooksConfigBits.wrap(
            HooksConfigBits.unwrap(config).insertBool(true, HooksConfigLib.AFTER_INITIALIZE_OFFSET)
        );
        assertEq(config.shouldCallAfterInitialize(), true, "shouldCallAfterInitialize should be true (getter)");
    }

    function testSetShouldCallAfterInitialize() public pure {
        HooksConfigBits config;
        config = config.setShouldCallAfterInitialize(true);
        assertEq(config.shouldCallAfterInitialize(), true, "shouldCallAfterInitialize should be true (setter)");
    }

    function testShouldCallComputeDynamicSwapFee() public pure {
        HooksConfigBits config;
        config = HooksConfigBits.wrap(
            HooksConfigBits.unwrap(config).insertBool(true, HooksConfigLib.DYNAMIC_SWAP_FEE_OFFSET)
        );
        assertEq(
            config.shouldCallComputeDynamicSwapFee(),
            true,
            "shouldCallComputeDynamicSwapFee should be true (getter)"
        );
    }

    function testSetShouldCallComputeDynamicSwapFee() public pure {
        HooksConfigBits config;
        config = config.setShouldCallComputeDynamicSwapFee(true);
        assertEq(
            config.shouldCallComputeDynamicSwapFee(),
            true,
            "shouldCallComputeDynamicSwapFee should be true (setter)"
        );
    }

    function testShouldCallBeforeSwap() public pure {
        HooksConfigBits config;
        config = HooksConfigBits.wrap(
            HooksConfigBits.unwrap(config).insertBool(true, HooksConfigLib.BEFORE_SWAP_OFFSET)
        );
        assertEq(config.shouldCallBeforeSwap(), true, "shouldCallBeforeSwap should be true (getter)");
    }

    function testSetShouldCallBeforeSwap() public pure {
        HooksConfigBits config;
        config = config.setShouldCallBeforeSwap(true);
        assertEq(config.shouldCallBeforeSwap(), true, "shouldCallBeforeSwap should be true (setter)");
    }

    function testShouldCallAfterSwap() public pure {
        HooksConfigBits config;
        config = HooksConfigBits.wrap(
            HooksConfigBits.unwrap(config).insertBool(true, HooksConfigLib.AFTER_SWAP_OFFSET)
        );
        assertEq(config.shouldCallAfterSwap(), true, "shouldCallAfterSwap should be true (getter)");
    }

    function testSetShouldCallAfterSwap() public pure {
        HooksConfigBits config;
        config = config.setShouldCallAfterSwap(true);
        assertEq(config.shouldCallAfterSwap(), true, "shouldCallAfterSwap should be true (setter)");
    }

    function testShouldCallBeforeAddLiquidity() public pure {
        HooksConfigBits config;
        config = HooksConfigBits.wrap(
            HooksConfigBits.unwrap(config).insertBool(true, HooksConfigLib.BEFORE_ADD_LIQUIDITY_OFFSET)
        );
        assertEq(config.shouldCallBeforeAddLiquidity(), true, "shouldCallBeforeAddLiquidity should be true (getter)");
    }

    function testSetShouldCallBeforeAddLiquidity() public pure {
        HooksConfigBits config;
        config = config.setShouldCallBeforeAddLiquidity(true);
        assertEq(config.shouldCallBeforeAddLiquidity(), true, "shouldCallBeforeAddLiquidity should be true (setter)");
    }

    function testShouldCallAfterAddLiquidity() public pure {
        HooksConfigBits config;
        config = HooksConfigBits.wrap(
            HooksConfigBits.unwrap(config).insertBool(true, HooksConfigLib.AFTER_ADD_LIQUIDITY_OFFSET)
        );
        assertEq(config.shouldCallAfterAddLiquidity(), true, "shouldCallAfterAddLiquidity should be true (getter)");
    }

    function testSetShouldCallAfterAddLiquidity() public pure {
        HooksConfigBits config;
        config = config.setShouldCallAfterAddLiquidity(true);
        assertEq(config.shouldCallAfterAddLiquidity(), true, "shouldCallAfterAddLiquidity should be true (setter)");
    }

    function testShouldCallBeforeRemoveLiquidity() public pure {
        HooksConfigBits config;
        config = HooksConfigBits.wrap(
            HooksConfigBits.unwrap(config).insertBool(true, HooksConfigLib.BEFORE_REMOVE_LIQUIDITY_OFFSET)
        );
        assertEq(
            config.shouldCallBeforeRemoveLiquidity(),
            true,
            "shouldCallBeforeRemoveLiquidity should be true (getter)"
        );
    }

    function testSetShouldCallBeforeRemoveLiquidity() public pure {
        HooksConfigBits config;
        config = config.setShouldCallBeforeRemoveLiquidity(true);
        assertEq(
            config.shouldCallBeforeRemoveLiquidity(),
            true,
            "shouldCallBeforeRemoveLiquidity should be true (setter)"
        );
    }

    function testShouldCallAfterRemoveLiquidity() public pure {
        HooksConfigBits config;
        config = HooksConfigBits.wrap(
            HooksConfigBits.unwrap(config).insertBool(true, HooksConfigLib.AFTER_REMOVE_LIQUIDITY_OFFSET)
        );
        assertEq(
            config.shouldCallAfterRemoveLiquidity(),
            true,
            "shouldCallAfterRemoveLiquidity should be true (getter)"
        );
    }

    function testSetShouldCallAfterRemoveLiquidity() public pure {
        HooksConfigBits config;
        config = config.setShouldCallAfterRemoveLiquidity(true);
        assertEq(
            config.shouldCallAfterRemoveLiquidity(),
            true,
            "shouldCallAfterRemoveLiquidity should be true (setter)"
        );
    }

    function testGetHooksContract() public view {
        HooksConfigBits config;
        config = HooksConfigBits.wrap(
            HooksConfigBits.unwrap(config).insertAddress(hooksContract, HooksConfigLib.HOOKS_CONTRACT_OFFSET)
        );
        assertEq(config.getHooksContract(), hooksContract, "getHooksContract should be hooksContract (getter)");
    }

    function testSetHooksContract() public view {
        HooksConfigBits config;
        config = config.setHooksContract(hooksContract);
        assertEq(config.getHooksContract(), hooksContract, "getHooksContract should be hooksContract (setter)");
    }
    // #endregion
}
