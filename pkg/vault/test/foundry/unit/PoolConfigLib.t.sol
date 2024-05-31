// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfig, PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

contract PoolConfigLibTest is Test {
    using WordCodec for bytes32;
    using PoolConfigLib for PoolConfig;

    uint24 private constant MAX_UINT24_VALUE = type(uint24).max;
    uint32 private constant MAX_UINT32_VALUE = type(uint32).max;
    uint256 constant TOKEN_DECIMAL_DIFFS_BITLENGTH = 24;
    uint8 constant DECIMAL_DIFF_BITLENGTH = 5;
    uint256 constant TIMESTAMP_BITLENGTH = 32;

    mapping(uint256 => bool) usedBits;

    // 7 flags + 3 * 24 bit fee + 24 bit token diffs + 32 bit timestamp = 135 total bits used.
    uint256 private constant BITS_IN_USE = 135;

    // #region PoolConfigBits

    function testGetStaticSwapFeePercentage() public {
        PoolConfig memory config;
        config.staticSwapFeePercentageUnscaled = MAX_UINT24_VALUE;

        assertEq(
            config.getStaticSwapFeePercentage(),
            MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "staticSwapFeePercentage mismatch (testGetStaticSwapFeePercentage)"
        );
    }

    function testSetStaticSwapFeePercentage() internal pure returns (uint256) {
        uint256 value = MAX_UINT24_VALUE * FEE_SCALING_FACTOR;

        PoolConfig memory config;
        config.setStaticSwapFeePercentage(value);

        assertEq(
            config.staticSwapFeePercentageUnscaled,
            MAX_UINT24_VALUE,
            "staticSwapFeePercentageUnscaled mismatch (testSetStaticSwapFeePercentage)"
        );
        assertEq(
            config.getStaticSwapFeePercentage(),
            value,
            "getStaticSwapFeePercentage mismatch (testSetStaticSwapFeePercentage)"
        );
    }

    function testGetAggregateProtocolSwapFeePercentage() public {
        PoolConfig memory config;
        config.aggregateProtocolSwapFeePercentageUnscaled = MAX_UINT24_VALUE;

        assertEq(
            config.getAggregateProtocolSwapFeePercentage(),
            MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "getAggregateProtocolSwapFeePercentage mismatch (testGetAggregateProtocolSwapFeePercentage)"
        );
    }

    function testSetAggregateProtocolSwapFeePercentage() internal pure returns (uint256) {
        uint256 value = MAX_UINT24_VALUE * FEE_SCALING_FACTOR;

        PoolConfig memory config;
        config.setAggregateProtocolSwapFeePercentage(value);

        assertEq(
            config.aggregateProtocolSwapFeePercentageUnscaled,
            MAX_UINT24_VALUE,
            "aggregateProtocolSwapFeePercentageUnscaled mismatch (testSetAggregateProtocolSwapFeePercentage)"
        );

        assertEq(
            config.getAggregateProtocolSwapFeePercentage(),
            value,
            "getAggregateProtocolSwapFeePercentage mismatch (testSetAggregateProtocolSwapFeePercentage)"
        );
    }

    function testGetAggregateProtocolYieldFeePercentage() public {
        PoolConfig memory config;
        config.aggregateProtocolYieldFeePercentageUnscaled = MAX_UINT24_VALUE;

        assertEq(
            config.getAggregateProtocolYieldFeePercentage(),
            MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "getAggregateProtocolYieldFeePercentage mismatch (testGetAggregateProtocolYieldFeePercentage)"
        );
    }

    function testSetAggregateProtocolYieldFeePercentage() internal pure returns (uint256) {
        uint256 value = MAX_UINT24_VALUE * FEE_SCALING_FACTOR;

        PoolConfig memory config;
        config.setAggregateProtocolYieldFeePercentage(value);

        assertEq(
            config.aggregateProtocolYieldFeePercentageUnscaled,
            MAX_UINT24_VALUE,
            "aggregateProtocolYieldFeePercentageUnscaled mismatch (testSetAggregateProtocolYieldFeePercentage)"
        );

        assertEq(
            config.getAggregateProtocolYieldFeePercentage(),
            value,
            "getAggregateProtocolYieldFeePercentage mismatch (testSetAggregateProtocolYieldFeePercentage)"
        );
    }

    // #endregion

    // #region PoolConfig
    function testRequireUnbalancedLiquidityEnabled() public pure {
        PoolConfig memory config;

        // It's enabled by default
        config.requireUnbalancedLiquidityEnabled();
    }

    function testRequireUnbalancedLiquidityEnabledIfIsDisabled() public {
        PoolConfig memory config;
        config.disableUnbalancedLiquidity = true;

        vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
        config.requireUnbalancedLiquidityEnabled();
    }

    function testRequireAddCustomLiquidityEnabled() public pure {
        PoolConfig memory config;
        config.enableAddLiquidityCustom = true;

        config.requireAddCustomLiquidityEnabled();
    }

    function testRequireAddCustomLiquidityEnabledIfIsDisabled() public {
        PoolConfig memory config;

        vm.expectRevert(IVaultErrors.DoesNotSupportAddLiquidityCustom.selector);
        config.requireAddCustomLiquidityEnabled();
    }

    function testRequireRemoveCustomLiquidityEnabled() public pure {
        PoolConfig memory config;
        config.enableRemoveLiquidityCustom = true;

        config.requireRemoveCustomLiquidityEnabled();
    }

    function testRequireRemoveCustomLiquidityEnabledIfIsDisabled() public {
        PoolConfig memory config;

        vm.expectRevert(IVaultErrors.DoesNotSupportRemoveLiquidityCustom.selector);
        config.requireRemoveCustomLiquidityEnabled();
    }

    function testToTokenDecimalDiffs() public {
        uint8[] memory tokenDecimalDiffs = new uint8[](2);
        tokenDecimalDiffs[0] = 1;
        tokenDecimalDiffs[1] = 2;

        uint256 value = uint256(
            bytes32(0).insertUint(tokenDecimalDiffs[0], 0, DECIMAL_DIFF_BITLENGTH).insertUint(
                tokenDecimalDiffs[1],
                DECIMAL_DIFF_BITLENGTH,
                DECIMAL_DIFF_BITLENGTH
            )
        );

        assertEq(
            PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs),
            value,
            "tokenDecimalDiffs mismatch (testToTokenDecimalDiffs)"
        );
    }

    function testGetDecimalScalingFactors() public {
        PoolConfig memory config;
        uint256 valueOne = 5;
        uint256 valueTwo = 20;

        config.tokenDecimalDiffs = uint24(
            uint256(
                bytes32(0).insertUint(valueOne, 0, DECIMAL_DIFF_BITLENGTH).insertUint(
                    valueTwo,
                    DECIMAL_DIFF_BITLENGTH,
                    DECIMAL_DIFF_BITLENGTH
                )
            )
        );

        uint256[] memory scalingFactors = config.getDecimalScalingFactors(2);

        assertEq(scalingFactors[0], 1e23, "scalingFactors[0] mismatch");
        assertEq(scalingFactors[1], 1e38, "scalingFactors[1] mismatch");
    }

    // #endregion
}
