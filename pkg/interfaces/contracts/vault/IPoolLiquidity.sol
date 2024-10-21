// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Interface for custom liquidity operations
interface IPoolLiquidity {
    /**
     * @notice Add liquidity to the pool with a custom hook.
     * @param router The address (usually a router contract) that initiated a swap operation on the Vault
     * @param maxAmountsInScaled18 Maximum input amounts, sorted in token registration order
     * @param minBptAmountOut Minimum amount of output pool tokens
     * @param balancesScaled18 Current pool balances, sorted in token registration order
     * @param userData Arbitrary data sent with the encoded request
     * @return amountsInScaled18 Input token amounts, sorted in token registration order
     * @return bptAmountOut Calculated pool token amount to receive
     * @return swapFeeAmountsScaled18 The amount of swap fees charged for each token
     * @return returnData Arbitrary data with an encoded response from the pool
     */
    function onAddLiquidityCustom(
        address router,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    )
        external
        returns (
            uint256[] memory amountsInScaled18,
            uint256 bptAmountOut,
            uint256[] memory swapFeeAmountsScaled18,
            bytes memory returnData
        );

    /**
     * @notice Remove liquidity from the pool with a custom hook.
     * @param router The address (usually a router contract) that initiated a swap operation on the Vault
     * @param maxBptAmountIn Maximum amount of input pool tokens
     * @param minAmountsOutScaled18 Minimum output amounts, sorted in token registration order
     * @param balancesScaled18 Current pool balances, sorted in token registration order
     * @param userData Arbitrary data sent with the encoded request
     * @return bptAmountIn Calculated pool token amount to burn
     * @return amountsOutScaled18 Amount of tokens to receive, sorted in token registration order
     * @return swapFeeAmountsScaled18 The amount of swap fees charged for each token
     * @return returnData Arbitrary data with an encoded response from the pool
     */
    function onRemoveLiquidityCustom(
        address router,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    )
        external
        returns (
            uint256 bptAmountIn,
            uint256[] memory amountsOutScaled18,
            uint256[] memory swapFeeAmountsScaled18,
            bytes memory returnData
        );
}
