// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IVault.sol";

interface IBasePool {
    event OnLiquidityAdded(
        address sender,
        uint256[] currentBalances,
        uint256[] maxAmountsIn,
        uint256 bptAmountOut,
        bytes userData
    );

    event OnLiquidityRemoved(address sender, uint256[] currentBalances, uint256 bptAmountIn, bytes userData);

    function onAddLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    function onRemoveLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);

    function onSwap(SwapParams calldata params) external returns (uint256 amountCalculated);

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
