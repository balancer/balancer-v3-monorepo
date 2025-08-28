// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SwapKind } from "./VaultTypes.sol";

struct AddLiquidityAndSwapParams {
    uint256[] maxAmountsIn;
    uint256 exactBptAmountOut;
    IERC20 swapTokenIn;
    IERC20 swapTokenOut;
    uint256 swapAmountGiven;
    uint256 swapLimit;
}

struct AddLiquidityAndSwapHookParams {
    address pool;
    address sender;
    uint256 deadline;
    bool wethIsEth;
    SwapKind swapKind;
    AddLiquidityAndSwapParams operationParams;
}
