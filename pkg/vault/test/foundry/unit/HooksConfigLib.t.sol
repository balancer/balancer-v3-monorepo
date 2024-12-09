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

        assertEq(config.enableHookAdjustedAmounts(), false, "enableHookAdjustedAmounts mismatch (zero config)");
        assertEq(config.shouldCallBeforeInitialize(), false, "shouldCallBeforeInitialize mismatch (zero config)");
        assertEq(config.shouldCallAfterInitialize(), false, "shouldCallAfterInitialize mismatch (zero config)");
        assertEq(
            config.shouldCallComputeDynamicSwapFee(),
            false,
            "shouldCallComputeDynamicSwapFee mismatch (zero config)"
        );
        assertEq(config.shouldCallBeforeSwap(), false, "shouldCallBeforeSwap mismatch (zero config)");
        assertEq(config.shouldCallAfterSwap(), false, "shouldCallAfterSwap mismatch (zero config)");
        assertEq(config.shouldCallBeforeAddLiquidity(), false, "shouldCallBeforeAddLiquidity mismatch (zero config)");
        assertEq(config.shouldCallAfterAddLiquidity(), false, "shouldCallAfterAddLiquidity mismatch (zero config)");
        assertEq(
            config.shouldCallBeforeRemoveLiquidity(),
            false,
            "shouldCallBeforeRemoveLiquidity mismatch (zero config)"
        );
        assertEq(
            config.shouldCallAfterRemoveLiquidity(),
            false,
            "shouldCallAfterRemoveLiquidity mismatch (zero config)"
        );
    }

    function testEnableHookAdjustedAmounts() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.ENABLE_HOOK_ADJUSTED_AMOUNTS_OFFSET)
        );
        assertTrue(config.enableHookAdjustedAmounts(), "enableHookAdjustedAmounts is false (getter)");
    }

    function testSetHookAdjustedAmounts() public pure {
        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);
        assertTrue(config.enableHookAdjustedAmounts(), "enableHookAdjustedAmounts is false (setter)");
    }

    function testShouldCallBeforeInitialize() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.BEFORE_INITIALIZE_OFFSET)
        );
        assertEq(config.shouldCallBeforeInitialize(), true, "shouldCallBeforeInitialize should be true (getter)");
    }

    function testSetShouldCallBeforeInitialize() public pure {
        PoolConfigBits config;
        config = config.setShouldCallBeforeInitialize(true);
        assertEq(config.shouldCallBeforeInitialize(), true, "shouldCallBeforeInitialize should be true (setter)");
    }

    function testShouldCallAfterInitialize() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.AFTER_INITIALIZE_OFFSET)
        );
        assertEq(config.shouldCallAfterInitialize(), true, "shouldCallAfterInitialize should be true (getter)");
    }

    function testSetShouldCallAfterInitialize() public pure {
        PoolConfigBits config;
        config = config.setShouldCallAfterInitialize(true);
        assertEq(config.shouldCallAfterInitialize(), true, "shouldCallAfterInitialize should be true (setter)");
    }

    function testShouldCallComputeDynamicSwapFee() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.DYNAMIC_SWAP_FEE_OFFSET)
        );
        assertEq(
            config.shouldCallComputeDynamicSwapFee(),
            true,
            "shouldCallComputeDynamicSwapFee should be true (getter)"
        );
    }

    function testSetShouldCallComputeDynamicSwapFee() public pure {
        PoolConfigBits config;
        config = config.setShouldCallComputeDynamicSwapFee(true);
        assertEq(
            config.shouldCallComputeDynamicSwapFee(),
            true,
            "shouldCallComputeDynamicSwapFee should be true (setter)"
        );
    }

    function testShouldCallBeforeSwap() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.BEFORE_SWAP_OFFSET)
        );
        assertEq(config.shouldCallBeforeSwap(), true, "shouldCallBeforeSwap should be true (getter)");
    }

    function testSetShouldCallBeforeSwap() public pure {
        PoolConfigBits config;
        config = config.setShouldCallBeforeSwap(true);
        assertEq(config.shouldCallBeforeSwap(), true, "shouldCallBeforeSwap should be true (setter)");
    }

    function testShouldCallAfterSwap() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.AFTER_SWAP_OFFSET));
        assertEq(config.shouldCallAfterSwap(), true, "shouldCallAfterSwap should be true (getter)");
    }

    function testSetShouldCallAfterSwap() public pure {
        PoolConfigBits config;
        config = config.setShouldCallAfterSwap(true);
        assertEq(config.shouldCallAfterSwap(), true, "shouldCallAfterSwap should be true (setter)");
    }

    function testShouldCallBeforeAddLiquidity() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.BEFORE_ADD_LIQUIDITY_OFFSET)
        );
        assertEq(config.shouldCallBeforeAddLiquidity(), true, "shouldCallBeforeAddLiquidity should be true (getter)");
    }

    function testSetShouldCallBeforeAddLiquidity() public pure {
        PoolConfigBits config;
        config = config.setShouldCallBeforeAddLiquidity(true);
        assertEq(config.shouldCallBeforeAddLiquidity(), true, "shouldCallBeforeAddLiquidity should be true (setter)");
    }

    function testShouldCallAfterAddLiquidity() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.AFTER_ADD_LIQUIDITY_OFFSET)
        );
        assertEq(config.shouldCallAfterAddLiquidity(), true, "shouldCallAfterAddLiquidity should be true (getter)");
    }

    function testSetShouldCallAfterAddLiquidity() public pure {
        PoolConfigBits config;
        config = config.setShouldCallAfterAddLiquidity(true);
        assertEq(config.shouldCallAfterAddLiquidity(), true, "shouldCallAfterAddLiquidity should be true (setter)");
    }

    function testShouldCallBeforeRemoveLiquidity() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.BEFORE_REMOVE_LIQUIDITY_OFFSET)
        );
        assertEq(
            config.shouldCallBeforeRemoveLiquidity(),
            true,
            "shouldCallBeforeRemoveLiquidity should be true (getter)"
        );
    }

    function testSetShouldCallBeforeRemoveLiquidity() public pure {
        PoolConfigBits config;
        config = config.setShouldCallBeforeRemoveLiquidity(true);
        assertEq(
            config.shouldCallBeforeRemoveLiquidity(),
            true,
            "shouldCallBeforeRemoveLiquidity should be true (setter)"
        );
    }

    function testShouldCallAfterRemoveLiquidity() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.AFTER_REMOVE_LIQUIDITY_OFFSET)
        );
        assertEq(
            config.shouldCallAfterRemoveLiquidity(),
            true,
            "shouldCallAfterRemoveLiquidity should be true (getter)"
        );
    }

    function testSetShouldCallAfterRemoveLiquidity() public pure {
        PoolConfigBits config;
        config = config.setShouldCallAfterRemoveLiquidity(true);
        assertEq(
            config.shouldCallAfterRemoveLiquidity(),
            true,
            "shouldCallAfterRemoveLiquidity should be true (setter)"
        );
    }

    function testToHooksConfig() public pure {
        address hooksContract = address(0x1234567890123456789012345678901234567890);

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);
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
        assertEq(hooksConfig.shouldCallBeforeInitialize, true, "shouldCallBeforeInitialize mismatch");
        assertEq(hooksConfig.shouldCallAfterInitialize, true, "shouldCallAfterInitialize mismatch");
        assertEq(hooksConfig.shouldCallComputeDynamicSwapFee, true, "shouldCallComputeDynamicSwapFee mismatch");

        assertEq(hooksConfig.shouldCallBeforeSwap, true, "shouldCallBeforeSwap mismatch");
        assertEq(hooksConfig.shouldCallAfterSwap, true, "shouldCallAfterSwap mismatch");
        assertEq(hooksConfig.shouldCallBeforeAddLiquidity, true, "shouldCallBeforeAddLiquidity mismatch");
        assertEq(hooksConfig.shouldCallAfterAddLiquidity, true, "shouldCallAfterAddLiquidity mismatch");
        assertEq(hooksConfig.shouldCallBeforeRemoveLiquidity, true, "shouldCallBeforeRemoveLiquidity mismatch");
        assertEq(hooksConfig.shouldCallAfterRemoveLiquidity, true, "shouldCallAfterRemoveLiquidity mismatch");
        assertEq(hooksConfig.hooksContract, hooksContract, "hooksContract mismatch");
    }
}
