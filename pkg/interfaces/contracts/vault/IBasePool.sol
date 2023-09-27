// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IVault.sol";

/// @notice Interface for a Base Pool
interface IBasePool {
    function supportsAddLiquidityProportional() external view returns (bool);

    function supportsRemoveLiquidityProportional() external view returns (bool);

    function onBeforeAdd(uint256[] memory currentBalances) external;

    function onBeforeRemove(uint256[] memory currentBalances) external;

    /**
     * @notice Add liquidity to the pool
     * @param sender               Address of the sender
     * @param currentBalances      Current balances of the tokens
     * @param maxAmountsIn         Maximum amounts of tokens to be added
     * @param userData             Additional data provided by the user
     * @return amountsIn           Actual amounts of tokens added
     * @return bptAmountOut        Amount of BPT tokens minted
     */
    function onAddLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    function onAddLiquidityUnbalanced(
        address sender,
        uint256[] memory exactAmountsIn,
        uint256[] memory currentBalances
    ) external returns (uint256 bptAmountOut);

    function onAddLiquiditySingleTokenInForExactBptOut(
        address sender,
        IERC20 tokenIn,
        uint256 exactBptAmountOut,
        uint256[] memory currentBalances
    ) external returns (uint256 amountIn);

    function onAddLiquidityCustom(
        address sender,
        bytes memory userData,
        uint256[] memory currentBalances
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);

    function onAfterAddLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory maxAmountsIn,
        bytes memory userData,
        uint256[] memory amountsIn,
        uint256 bptAmountOut
    ) external returns (bool success);

    /**
     * @notice Remove liquidity from the pool
     * @param sender               Address of the sender
     * @param currentBalances      Current balances of the tokens
     * @param minAmountsOut        Minimum amounts of tokens to be removed
     * @param bptAmountIn          Amount of BPT tokens burnt
     * @param userData             Additional data provided by the user
     * @return amountsOut          Actual amounts of tokens removed
     */
    function onRemoveLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);

    function onAfterRemoveLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData,
        uint256[] memory amountsOut
    ) external returns (bool success);

    /**
     * @notice Execute a swap in the pool
     * @param params               Parameters of the swap
     * @return amountCalculated    Calculated amount after the swap
     */
    function onSwap(SwapParams calldata params) external returns (uint256 amountCalculated);

    /// @notice Parameters for a swap operation
    struct SwapParams {
        /// @notice Type of swap (given in or given out)
        IVault.SwapKind kind;
        /// @notice Token given in the swap
        IERC20 tokenIn;
        /// @notice Token received from the swap
        IERC20 tokenOut;
        /// @notice Amount of `tokenIn` given
        uint256 amountGiven;
        /// @notice Current balances of all tokens in the pool
        uint256[] balances;
        /// @notice Index of `tokenIn` in the list of pool tokens
        uint256 indexIn;
        /// @notice Index of `tokenOut` in the list of pool tokens
        uint256 indexOut;
        /// @notice Address of the sender
        address sender;
        /// @notice Additional data provided by the user
        bytes userData;
    }

    /**
     * @notice Called after a swap to give the Pool an opportunity to perform actions
     * once the balances have been updated by the swap.
     * @param params               Parameters of the swap
     * @param amountCalculated     Calculated amount after the swap
     * @return success             True if call was a success
     */
    function onAfterSwap(AfterSwapParams calldata params, uint256 amountCalculated) external returns (bool success);

    struct AfterSwapParams {
        IVault.SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 tokenInBalance;
        uint256 tokenOutBalance;
        address sender;
        bytes userData;
    }
}
