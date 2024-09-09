// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { PoolConfigBits, HooksConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfigConst } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigConst.sol";
import { HooksConfigLib } from "@balancer-labs/v3-vault/contracts/lib/HooksConfigLib.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

contract HooksConfigLibTest is Test {
    using WordCodec for bytes32;
    using HooksConfigLib for PoolConfigBits;

    function testZeroConfigBytes() public pure {
        PoolConfigBits config;

        assertFalse(config.enableHookAdjustedAmountsOnAdd(), "enableHookAdjustedAmountsOnAdd mismatch (zero config)");
        assertFalse(
            config.enableHookAdjustedAmountsOnRemove(),
            "enableHookAdjustedAmountsOnRemove mismatch (zero config)"
        );
        assertFalse(config.enableHookAdjustedAmountsOnSwap(), "enableHookAdjustedAmountsOnSwap mismatch (zero config)");
        assertFalse(config.shouldCallBeforeInitialize(), "shouldCallBeforeInitialize mismatch (zero config)");
        assertFalse(config.shouldCallAfterInitialize(), "shouldCallAfterInitialize mismatch (zero config)");
        assertFalse(config.shouldCallComputeDynamicSwapFee(), "shouldCallComputeDynamicSwapFee mismatch (zero config)");
        assertFalse(config.shouldCallBeforeSwap(), "shouldCallBeforeSwap mismatch (zero config)");
        assertFalse(config.shouldCallAfterSwap(), "shouldCallAfterSwap mismatch (zero config)");
        assertFalse(config.shouldCallBeforeAddLiquidity(), "shouldCallBeforeAddLiquidity mismatch (zero config)");
        assertFalse(config.shouldCallAfterAddLiquidity(), "shouldCallAfterAddLiquidity mismatch (zero config)");
        assertFalse(config.shouldCallBeforeRemoveLiquidity(), "shouldCallBeforeRemoveLiquidity mismatch (zero config)");
        assertFalse(config.shouldCallAfterRemoveLiquidity(), "shouldCallAfterRemoveLiquidity mismatch (zero config)");
    }

    function testEnableHookAdjustedAmountsOnAdd() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.ENABLE_HOOK_ADJUSTED_AMOUNTS_ADD_OFFSET)
        );
        assertTrue(config.enableHookAdjustedAmountsOnAdd(), "enableHookAdjustedAmountsOnAdd is false (getter)");
    }

    function testEnableHookAdjustedAmountsOnRemove() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.ENABLE_HOOK_ADJUSTED_AMOUNTS_REMOVE_OFFSET)
        );
        assertTrue(config.enableHookAdjustedAmountsOnRemove(), "enableHookAdjustedAmountsOnRemove is false (getter)");
    }

    function testEnableHookAdjustedAmountsOnSwap() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.ENABLE_HOOK_ADJUSTED_AMOUNTS_SWAP_OFFSET)
        );
        assertTrue(config.enableHookAdjustedAmountsOnSwap(), "enableHookAdjustedAmountsOnSwap is false (getter)");
    }

    function testSetHookAdjustedAmountsOnAdd() public pure {
        PoolConfigBits config;
        config = config.setHookAdjustedAmountsOnAdd(true);
        assertTrue(config.enableHookAdjustedAmountsOnAdd(), "enableHookAdjustedAmountsOnAdd is false (setter)");
    }

    function testSetHookAdjustedAmountsOnRemove() public pure {
        PoolConfigBits config;
        config = config.setHookAdjustedAmountsOnRemove(true);
        assertTrue(config.enableHookAdjustedAmountsOnRemove(), "enableHookAdjustedAmountsOnRemove is false (setter)");
    }

    function testSetHookAdjustedAmountsOnSwap() public pure {
        PoolConfigBits config;
        config = config.setHookAdjustedAmountsOnSwap(true);
        assertTrue(config.enableHookAdjustedAmountsOnSwap(), "enableHookAdjustedAmountsOnSwap is false (setter)");
    }

    function testShouldCallBeforeInitialize() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.BEFORE_INITIALIZE_OFFSET)
        );
        assertTrue(config.shouldCallBeforeInitialize(), "shouldCallBeforeInitialize should be true (getter)");
    }

    function testSetShouldCallBeforeInitialize() public pure {
        PoolConfigBits config;
        config = config.setShouldCallBeforeInitialize(true);
        assertTrue(config.shouldCallBeforeInitialize(), "shouldCallBeforeInitialize should be true (setter)");
    }

    function testShouldCallAfterInitialize() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.AFTER_INITIALIZE_OFFSET)
        );
        assertTrue(config.shouldCallAfterInitialize(), "shouldCallAfterInitialize should be true (getter)");
    }

    function testSetShouldCallAfterInitialize() public pure {
        PoolConfigBits config;
        config = config.setShouldCallAfterInitialize(true);
        assertTrue(config.shouldCallAfterInitialize(), "shouldCallAfterInitialize should be true (setter)");
    }

    function testShouldCallComputeDynamicSwapFee() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.DYNAMIC_SWAP_FEE_OFFSET)
        );
        assertTrue(config.shouldCallComputeDynamicSwapFee(), "shouldCallComputeDynamicSwapFee should be true (getter)");
    }

    function testSetShouldCallComputeDynamicSwapFee() public pure {
        PoolConfigBits config;
        config = config.setShouldCallComputeDynamicSwapFee(true);
        assertTrue(config.shouldCallComputeDynamicSwapFee(), "shouldCallComputeDynamicSwapFee should be true (setter)");
    }

    function testShouldCallBeforeSwap() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.BEFORE_SWAP_OFFSET)
        );
        assertTrue(config.shouldCallBeforeSwap(), "shouldCallBeforeSwap should be true (getter)");
    }

    function testSetShouldCallBeforeSwap() public pure {
        PoolConfigBits config;
        config = config.setShouldCallBeforeSwap(true);
        assertTrue(config.shouldCallBeforeSwap(), "shouldCallBeforeSwap should be true (setter)");
    }

    function testShouldCallAfterSwap() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.AFTER_SWAP_OFFSET));
        assertTrue(config.shouldCallAfterSwap(), "shouldCallAfterSwap should be true (getter)");
    }

    function testSetShouldCallAfterSwap() public pure {
        PoolConfigBits config;
        config = config.setShouldCallAfterSwap(true);
        assertTrue(config.shouldCallAfterSwap(), "shouldCallAfterSwap should be true (setter)");
    }

    function testShouldCallBeforeAddLiquidity() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.BEFORE_ADD_LIQUIDITY_OFFSET)
        );
        assertTrue(config.shouldCallBeforeAddLiquidity(), "shouldCallBeforeAddLiquidity should be true (getter)");
    }

    function testSetShouldCallBeforeAddLiquidity() public pure {
        PoolConfigBits config;
        config = config.setShouldCallBeforeAddLiquidity(true);
        assertTrue(config.shouldCallBeforeAddLiquidity(), "shouldCallBeforeAddLiquidity should be true (setter)");
    }

    function testShouldCallAfterAddLiquidity() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.AFTER_ADD_LIQUIDITY_OFFSET)
        );
        assertTrue(config.shouldCallAfterAddLiquidity(), "shouldCallAfterAddLiquidity should be true (getter)");
    }

    function testSetShouldCallAfterAddLiquidity() public pure {
        PoolConfigBits config;
        config = config.setShouldCallAfterAddLiquidity(true);
        assertTrue(config.shouldCallAfterAddLiquidity(), "shouldCallAfterAddLiquidity should be true (setter)");
    }

    function testShouldCallBeforeRemoveLiquidity() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.BEFORE_REMOVE_LIQUIDITY_OFFSET)
        );
        assertTrue(config.shouldCallBeforeRemoveLiquidity(), "shouldCallBeforeRemoveLiquidity should be true (getter)");
    }

    function testSetShouldCallBeforeRemoveLiquidity() public pure {
        PoolConfigBits config;
        config = config.setShouldCallBeforeRemoveLiquidity(true);
        assertTrue(config.shouldCallBeforeRemoveLiquidity(), "shouldCallBeforeRemoveLiquidity should be true (setter)");
    }

    function testShouldCallAfterRemoveLiquidity() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.AFTER_REMOVE_LIQUIDITY_OFFSET)
        );
        assertTrue(config.shouldCallAfterRemoveLiquidity(), "shouldCallAfterRemoveLiquidity should be true (getter)");
    }

    function testSetShouldCallAfterRemoveLiquidity() public pure {
        PoolConfigBits config;
        config = config.setShouldCallAfterRemoveLiquidity(true);
        assertTrue(config.shouldCallAfterRemoveLiquidity(), "shouldCallAfterRemoveLiquidity should be true (setter)");
    }

    function testToHooksConfig() public pure {
        address hooksContract = address(0x1234567890123456789012345678901234567890);

        PoolConfigBits config;
        config = config.setHookAdjustedAmountsOnAdd(true);
        config = config.setHookAdjustedAmountsOnRemove(true);
        config = config.setHookAdjustedAmountsOnSwap(true);
        config = config.setShouldCallBeforeInitialize(true);
        config = config.setShouldCallAfterInitialize(true);
        config = config.setShouldCallComputeDynamicSwapFee(true);
        config = config.setShouldCallBeforeSwap(true);
        config = config.setShouldCallAfterSwap(true);
        config = config.setShouldCallBeforeAddLiquidity(true);
        config = config.setShouldCallAfterAddLiquidity(true);
        config = config.setShouldCallBeforeRemoveLiquidity(true);
        config = config.setShouldCallAfterRemoveLiquidity(true);

        HooksConfig memory hooksConfig = config.toHooksConfig(IHooks(hooksContract));
        assertTrue(hooksConfig.shouldCallBeforeInitialize, "shouldCallBeforeInitialize mismatch");
        assertTrue(hooksConfig.shouldCallAfterInitialize, "shouldCallAfterInitialize mismatch");
        assertTrue(hooksConfig.shouldCallComputeDynamicSwapFee, "shouldCallComputeDynamicSwapFee mismatch");
        assertTrue(hooksConfig.shouldCallBeforeSwap, "shouldCallBeforeSwap mismatch");
        assertTrue(hooksConfig.shouldCallAfterSwap, "shouldCallAfterSwap mismatch");
        assertTrue(hooksConfig.shouldCallBeforeAddLiquidity, "shouldCallBeforeAddLiquidity mismatch");
        assertTrue(hooksConfig.shouldCallAfterAddLiquidity, "shouldCallAfterAddLiquidity mismatch");
        assertTrue(hooksConfig.shouldCallBeforeRemoveLiquidity, "shouldCallBeforeRemoveLiquidity mismatch");
        assertTrue(hooksConfig.shouldCallAfterRemoveLiquidity, "shouldCallAfterRemoveLiquidity mismatch");
        assertEq(hooksConfig.hooksContract, hooksContract, "hooksContract mismatch");
    }
}
