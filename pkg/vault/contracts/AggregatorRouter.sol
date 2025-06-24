// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IAggregatorRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IAggregatorRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

import { SenderGuard } from "./SenderGuard.sol";
import { Router } from "./Router.sol";
import { VaultGuard } from "./VaultGuard.sol";

/**
 * @notice Entrypoint for aggregators who want to swap without the standard permit2 payment logic.
 * @dev The external API functions unlock the Vault, which calls back into the corresponding hook functions.
 * These interact with the Vault and settle accounting. This is not a full-featured Router; it only implements
 * `swapSingleTokenExactIn`, `swapSingleTokenExactOut`, and the associated queries.
 */
contract AggregatorRouter is IAggregatorRouter, Router {
    constructor(
        IVault vault,
        string memory routerVersion
    ) Router(vault, IWETH(address(0)), IPermit2(address(0)), true, routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    /// @inheritdoc IAggregatorRouter
    /// @dev Backwards compatibility with the old interface.
    function swapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bytes calldata userData
    ) external returns (uint256) {
        return swapSingleTokenExactIn(pool, tokenIn, tokenOut, exactAmountIn, minAmountOut, deadline, false, userData);
    }

    /// @inheritdoc IAggregatorRouter
    function swapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bytes calldata userData
    ) external returns (uint256) {
        return swapSingleTokenExactOut(pool, tokenIn, tokenOut, exactAmountOut, maxAmountIn, deadline, false, userData);
    }
}
