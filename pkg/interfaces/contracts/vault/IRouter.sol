// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { AddLiquidityKind, RemoveLiquidityKind, SwapKind } from "./VaultTypes.sol";

import { IRouterMain } from "./IRouterMain.sol";
import { IRouterExtension } from "./IRouterExtension.sol";

/// @notice User-friendly interface to basic Vault operations: swap, add/remove liquidity, and associated queries.
interface IRouter is IRouterMain, IRouterExtension {
    // solhint-disable-previous-line no-empty-blocks
}
