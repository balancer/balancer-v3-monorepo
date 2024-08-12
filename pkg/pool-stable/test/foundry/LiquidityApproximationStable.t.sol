// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";

import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { LiquidityApproximationTest } from "@balancer-labs/v3-vault/test/foundry/LiquidityApproximation.t.sol";

import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";

contract LiquidityApproximationStableTest is LiquidityApproximationTest {
    using CastingHelpers for address[];

    uint256 poolCreationNonce;
    uint256 constant DEFAULT_AMP_FACTOR = 200;

    function setUp() public virtual override {
        LiquidityApproximationTest.setUp();

        // Grants access to admin to change the amplification parameter of the pool.
        authorizer.grantRole(
            IAuthentication(liquidityPool).getActionId(StablePool.startAmplificationParameterUpdate.selector),
            admin
        );
        authorizer.grantRole(
            IAuthentication(swapPool).getActionId(StablePool.startAmplificationParameterUpdate.selector),
            admin
        );
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        StablePoolFactory factory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        PoolRoleAccounts memory roleAccounts;

        // Allow pools created by `factory` to use PoolHooksMock hooks.
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        StablePool newPool = StablePool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                vault.buildTokenConfig(tokens.asIERC20()),
                DEFAULT_AMP_FACTOR,
                roleAccounts,
                MIN_SWAP_FEE,
                poolHooksContract,
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                ZERO_BYTES32
            )
        );
        vm.label(address(newPool), label);
        return address(newPool);
    }

    // Tests varying Amplification Parameter

    function testAddLiquidityUnbalancedAmplificationParameter__Fuzz(
        uint256 daiAmountIn,
        uint256 swapFeePercentage,
        uint256 newAmplificationParameter
    ) public {
        swapFeePercentage = _setAmplificationParameterAndSwapFee(swapFeePercentage, newAmplificationParameter);

        uint256 amountOut = executeAddUnbalancedRemoveProportionalVsSwap(daiAmountIn, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, true);
    }

    function testAddLiquiditySingleTokenExactOutAmplificationParameter__Fuzz(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage,
        uint256 newAmplificationParameter
    ) public {
        swapFeePercentage = _setAmplificationParameterAndSwapFee(swapFeePercentage, newAmplificationParameter);

        uint256 amountOut = executeAddSingleTokenExactOutRemoveProportionalVsSwap(exactBptAmountOut, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, true);
    }

    function testAddLiquidityProportionalAndRemoveExactInAmplificationParameter__Fuzz(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage,
        uint256 newAmplificationParameter
    ) public {
        swapFeePercentage = _setAmplificationParameterAndSwapFee(swapFeePercentage, newAmplificationParameter);

        uint256 amountOut = executeAddProportionalRemoveExactInVsSwap(exactBptAmountOut, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    function testAddLiquidityProportionalAndRemoveExactOutAmplificationParameter__Fuzz(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage,
        uint256 newAmplificationParameter
    ) public {
        swapFeePercentage = _setAmplificationParameterAndSwapFee(swapFeePercentage, newAmplificationParameter);

        uint256 amountOut = executeAddProportionalRemoveExactOutVsSwap(exactBptAmountOut, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    function testRemoveLiquiditySingleTokenExactOutAmplificationParameter__Fuzz(
        uint256 exactAmountOut,
        uint256 swapFeePercentage,
        uint256 newAmplificationParameter
    ) public {
        swapFeePercentage = _setAmplificationParameterAndSwapFee(swapFeePercentage, newAmplificationParameter);

        uint256 amountOut = executeAddProportionalRemoveExactOutRemoveAllVsSwap(exactAmountOut, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    function testRemoveLiquiditySingleTokenExactInAmplificationParameter__Fuzz(
        uint256 exactBptAmountIn,
        uint256 swapFeePercentage,
        uint256 newAmplificationParameter
    ) public {
        swapFeePercentage = _setAmplificationParameterAndSwapFee(swapFeePercentage, newAmplificationParameter);

        uint256 amountOut = executeAddProportionalRemoveExactInRemoveAllVsSwap(exactBptAmountIn, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    /// Utils

    function _setAmplificationParameterAndSwapFee(
        uint256 swapFeePercentage,
        uint256 newAmplificationParameter
    ) private returns (uint256) {
        // Vary amplification parameter from 1 to 5000.
        newAmplificationParameter = bound(newAmplificationParameter, StableMath.MIN_AMP, StableMath.MAX_AMP);

        _setAmplificationParameter(liquidityPool, newAmplificationParameter);
        _setAmplificationParameter(swapPool, newAmplificationParameter);

        // Vary swap fee from 0.0001% (min swap fee) - 10% (max swap fee).
        swapFeePercentage = bound(swapFeePercentage, 1e12, maxSwapFeePercentage);
        return swapFeePercentage;
    }

    function _setAmplificationParameter(address pool, uint256 newAmplificationParameter) private {
        uint256 updateInterval = 5000 days;

        vm.prank(admin);
        StablePool(pool).startAmplificationParameterUpdate(newAmplificationParameter, block.timestamp + updateInterval);
        vm.warp(block.timestamp + updateInterval + 1);

        (uint256 value, bool isUpdating, uint256 precision) = StablePool(pool).getAmplificationParameter();
        assertFalse(isUpdating, "Pool amplification parameter is updating");
        assertEq(value / precision, newAmplificationParameter, "Amplification Parameter is wrong");
    }
}
