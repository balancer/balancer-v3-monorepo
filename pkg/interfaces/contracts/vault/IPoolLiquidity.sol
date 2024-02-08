// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "./IVault.sol";

/// @notice Interface for custom liquidity operations
interface IPoolLiquidity {
    /**
     * @notice Add liquidity to the pool with a custom handler.
     * @param sender Address of the sender
     * @param maxAmountsInScaled18 Maximum input amounts, in the same order as the tokens registered in the pool
     * @param minBptAmountOut Minimum amount of output pool tokens
     * @param balancesScaled18 Current pool balances, in the same order as the tokens registered in the pool
     * @param userData Arbitrary data with the encoded request
     * @return amountsInScaled18 Input token amounts, in the same order as the tokens registered in the pool
     * @return bptAmountOut Calculated pool token amount to receive
     * @return swapFeeAmountsScaled18 Swap fee amounts charge on each token
     * @return returnData Arbitrary data with encoded response from the pool
     */
    function onAddLiquidityCustom(
        address sender,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (uint256[] memory amountsInScaled18, uint256
    bptAmountOut, uint256[] memory swapFeeAmountsScaled18, bytes memory returnData);

    /**
     * @notice Remove liquidity from the pool with a custom handler.
     * @param sender Address of the sender
     * @param maxBptAmountIn Maximum amount of input pool tokens
     * @param minAmountsOutScaled18 Minimum output amounts, in the same order as the tokens registered in the pool
     * @param balancesScaled18 Current pool balances, in the same order as the tokens registered in the pool
     * @param userData Arbitrary data with the encoded request
     * @return bptAmountIn Calculated pool token amount to burn
     * @return amountsOutScaled18 Amount of tokens to receive, in the same order as the tokens registered in the pool
     * @return returnData Arbitrary data with encoded response from the pool
     */
    function onRemoveLiquidityCustom(
        address sender,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (uint256 bptAmountIn, uint256[] memory amountsOutScaled18, bytes memory returnData);
}
