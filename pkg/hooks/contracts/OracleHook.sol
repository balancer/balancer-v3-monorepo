// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { BasePoolHooks } from "@balancer-labs/v3-vault/contracts/BasePoolHooks.sol";

contract OracleHook is BasePoolHooks {
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;
    using ScalingHelpers for IERC20;

    mapping(IERC20 token => uint256 scalingFactor) public tokenScalingFactors;

    constructor(IVault vault) BasePoolHooks(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory tokenConfig,
        LiquidityManagement calldata
    ) external override onlyVault returns (bool) {
        // Revert if a pool has more than two tokens.
        if (tokenConfig.length > 2) return false;

        // Compute scaling factor for new tokens.
        if (tokenScalingFactors[tokenConfig[0].token] == 0) {
            tokenScalingFactors[tokenConfig[0].token] = tokenConfig[0].token.computeScalingFactor();
        }
        if (tokenScalingFactors[tokenConfig[1].token] == 0) {
            tokenScalingFactors[tokenConfig[1].token] = tokenConfig[1].token.computeScalingFactor();
        }

        return true;
    }

    function getHookFlags() external pure override returns (HookFlags memory) {
        return
            HookFlags({
                shouldCallBeforeInitialize: false,
                shouldCallAfterInitialize: false,
                shouldCallComputeDynamicSwapFee: false,
                shouldCallBeforeSwap: true, // TODO: Set to false
                shouldCallAfterSwap: true,
                shouldCallBeforeAddLiquidity: false,
                shouldCallAfterAddLiquidity: false,
                shouldCallBeforeRemoveLiquidity: false,
                shouldCallAfterRemoveLiquidity: false
            });
    }

    function onBeforeSwap(IBasePool.PoolSwapParams calldata params) external view override returns (bool success) {
        console.log("onBeforeSwap");
        console.log("amountGivenScaled18: %s", params.amountGivenScaled18);
        console.log("balancesScaled18: %s %s", params.balancesScaled18[0], params.balancesScaled18[1]);
        return true;
    }

    function onAfterSwap(
        IHooks.AfterSwapParams calldata params,
        uint256 amountCalculatedScaled18
    ) external view override returns (bool success) {
        console.log("onAfterSwap");
        console.log("amountInScaled18: %s", params.amountInScaled18);
        console.log("amountOutScaled18: %s", params.amountOutScaled18);
        console.log("tokenInBalanceScaled18: %s", params.tokenInBalanceScaled18);
        console.log("tokenOutBalanceScaled18: %s", params.tokenOutBalanceScaled18);
        console.log("amountCalculatedScaled18: %s", amountCalculatedScaled18); // NOTE: Redundant parameter

        // NOTE: Calculating swap prices without fees requires the `onSwap` return value
        uint256 swapPriceWithFeeScaled18;
        uint256 spotPriceScaled18;
        uint256 swapPriceWithFee;
        uint256 spotPrice;
        bool zeroForOne = params.tokenIn < params.tokenOut;
        // NOTE: `toRawRoundDown` doesn't account for token rates
        // `vault` could be queried with `pool` to get the token rates or raw balances (not scaled, not rated)
        if (zeroForOne) {
            swapPriceWithFeeScaled18 = params.amountInScaled18.divDown(params.amountOutScaled18);
            spotPriceScaled18 = params.tokenInBalanceScaled18.divDown(params.tokenOutBalanceScaled18);
            swapPriceWithFee = swapPriceWithFeeScaled18.toRawRoundDown(tokenScalingFactors[params.tokenIn]);
            spotPrice = spotPriceScaled18.toRawRoundDown(tokenScalingFactors[params.tokenIn]);
        } else {
            swapPriceWithFeeScaled18 = params.amountOutScaled18.divDown(params.amountInScaled18);
            spotPriceScaled18 = params.tokenOutBalanceScaled18.divDown(params.tokenInBalanceScaled18);
            swapPriceWithFee = swapPriceWithFeeScaled18.toRawRoundDown(tokenScalingFactors[params.tokenOut]);
            spotPrice = spotPriceScaled18.toRawRoundDown(tokenScalingFactors[params.tokenOut]);
        }
        console.log("swapPriceWithFeeScaled18: %s", swapPriceWithFeeScaled18);
        console.log("spotPriceScaled18: %s", spotPriceScaled18);
        console.log("swapPriceWithFee: %s", swapPriceWithFee);
        console.log("spotPrice: %s", spotPrice);
        return true;
    }
}
