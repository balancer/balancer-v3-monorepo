// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IVault.sol";

/**
 * @notice Interface defining the basic functions for a liquidity pool
 */
interface IBasePool {
    /**
     * @notice Emitted when liquidity is added to the pool
     * @param sender             Address of the entity adding liquidity
     * @param currentBalances    Balances of each token in the pool
     * @param maxAmountsIn       Max amounts to be deposited for each token
     * @param bptAmountOut       Amount of pool tokens minted
     * @param userData           Additional data passed by the user
     */
    event OnLiquidityAdded(
        address sender,
        uint256[] currentBalances,
        uint256[] maxAmountsIn,
        uint256 bptAmountOut,
        bytes userData
    );

    /**
     * @notice Emitted when liquidity is removed from the pool
     * @param sender             Address of the entity removing liquidity
     * @param currentBalances    Balances of each token remaining in the pool
     * @param bptAmountIn        Amount of pool tokens burned
     * @param userData           Additional data passed by the user
     */
    event OnLiquidityRemoved(address sender, uint256[] currentBalances, uint256 bptAmountIn, bytes userData);

    /**
     * @notice Handle liquidity addition to the pool
     * @param sender             Address of the entity adding liquidity
     * @param currentBalances    Balances of each token in the pool
     * @param maxAmountsIn       Max amounts to be deposited for each token
     * @param userData           Additional data passed by the user
     * @return amountsIn         Actual amounts deposited for each token
     * @return bptAmountOut      Amount of pool tokens minted
     */
    function onAddLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /**
     * @notice Handle liquidity removal from the pool
     * @param sender             Address of the entity removing liquidity
     * @param currentBalances    Balances of each token remaining in the pool
     * @param minAmountsOut      Minimum amounts to be withdrawn for each token
     * @param bptAmountIn        Amount of pool tokens to be burned
     * @param userData           Additional data passed by the user
     * @return amountsOut        Actual amounts withdrawn for each token
     */
    function onRemoveLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);

    /**
     * @notice Handle a swap operation in the pool
     * @param params             Struct containing swap parameters
     * @return amountCalculated  Amount of the token to be received
     */
    function onSwap(SwapParams calldata params) external returns (uint256 amountCalculated);

    /**
     * @notice Struct defining the parameters for a swap operation
     * @param kind               Kind of the swap (given by the IVault interface)
     * @param tokenIn            Token to be given
     * @param tokenOut           Token to be received
     * @param amountGiven        Amount of the token to be given
     * @param balances           Balances of each token in the pool
     * @param indexIn            Index of the token to be given in the pool's array
     * @param indexOut           Index of the token to be received in the pool's array
     * @param sender             Address of the entity initiating the swap
     * @param userData           Additional data passed by the user
     */
    struct SwapParams {
        IVault.SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountGiven;
        uint256[] balances;
        uint256 indexIn;
        uint256 indexOut;
        address sender;
        bytes userData;
    }
}
