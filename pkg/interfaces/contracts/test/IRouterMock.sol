// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "../vault/IRouter.sol";
import { IRouterCommon } from "../vault/IRouterCommon.sol";
import { IRouterExtension } from "../vault/IRouterExtension.sol";

/// @dev One-fits-all solution for hardhat tests. Use the typechain type for errors, events and functions.
interface IRouterMock is IRouter, IRouterCommon {
    function getSingleInputArrayAndTokenIndex(
        address pool,
        IERC20 token,
        uint256 amountGiven
    ) external view returns (uint256[] memory amountsGiven, uint256 tokenIndex);

    function manualReentrancyInitializeHook() external;

    function manualReentrancyAddLiquidityHook() external;

    function manualReentrancyRemoveLiquidityHook() external;

    function manualReentrancyRemoveLiquidityRecoveryHook() external;

    function manualReentrancySwapSingleTokenHook() external;

    function manualReentrancyAddLiquidityToBufferHook() external;

    function manualReentrancyQuerySwapHook() external;
}
