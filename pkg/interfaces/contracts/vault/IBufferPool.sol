// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SwapKind } from "./VaultTypes.sol";

/// @notice Interface for an ERC4626BufferPool
interface IBufferPool {
    /// @notice Explicitly rebalance a Buffer Pool, outside of a swap operation. This is a permissioned function.
    function rebalance() external;
}

struct RebalanceHookParams {
    address pool;
    SwapKind kind;
    IERC20 tokenIn;
    IERC20 tokenOut;
    uint256 amountGivenRaw;
    uint256 limit;
}
