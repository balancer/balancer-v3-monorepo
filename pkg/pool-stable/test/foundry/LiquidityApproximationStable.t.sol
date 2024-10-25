// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";

import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { LiquidityApproximationTest } from "@balancer-labs/v3-vault/test/foundry/LiquidityApproximation.t.sol";

import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";
import { StablePoolContractsDeployer } from "./utils/StablePoolContractsDeployer.sol";

contract LiquidityApproximationStableTest is LiquidityApproximationTest, StablePoolContractsDeployer {
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

        minSwapFeePercentage = IBasePool(swapPool).getMinimumSwapFeePercentage();
        maxSwapFeePercentage = IBasePool(swapPool).getMaximumSwapFeePercentage();
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        StablePoolFactory factory = deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
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
                0.01e16, // Initial swap fee: 0.01%
                poolHooksContract,
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                ZERO_BYTES32
            )
        );
        vm.label(address(newPool), label);
        return address(newPool);
    }

    function fuzzPoolParams(uint256[10] memory params) internal override {
        // Vary amplification parameter from 1 to 5000.
        uint256 newAmplificationParameter = bound(params[0], StableMath.MIN_AMP, StableMath.MAX_AMP);

        _setAmplificationParameter(liquidityPool, newAmplificationParameter);
        _setAmplificationParameter(swapPool, newAmplificationParameter);
    }

    // Tests varying Amplification Parameter

    //    function testRemoveLiquiditySingleTokenExactOutAmplificationParameter__Fuzz(
    //        uint256 exactAmountOut,
    //        uint256 swapFeePercentage,
    //        uint256 newAmplificationParameter
    //    ) public {
    //        exactAmountOut = bound(exactAmountOut, minAmount, maxAmount);
    //        swapFeePercentage = _setAmplificationParameterAndSwapFee(swapFeePercentage, newAmplificationParameter);
    //
    //        uint256 amountOut = removeExactOutArbitraryAmountOut(exactAmountOut, swapFeePercentage);
    //        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    //    }
    //
    //    function testRemoveLiquiditySingleTokenExactInAmplificationParameter__Fuzz(
    //        uint256 exactBptAmountIn,
    //        uint256 swapFeePercentage,
    //        uint256 newAmplificationParameter
    //    ) public {
    //        exactBptAmountIn = bound(exactBptAmountIn, minAmount, maxAmount);
    //        swapFeePercentage = _setAmplificationParameterAndSwapFee(swapFeePercentage, newAmplificationParameter);
    //
    //        uint256 amountOut = removeExactInArbitraryBptIn(exactBptAmountIn, swapFeePercentage);
    //        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    //    }

    // Utils

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
