// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BufferRouter } from "../BufferRouter.sol";

string constant MOCK_ROUTER_VERSION = "Mock Router v1";

contract BufferRouterMock is BufferRouter {
    error MockErrorCode();

    constructor(IVault vault, IWETH weth, IPermit2 permit2) BufferRouter(vault, weth, permit2, MOCK_ROUTER_VERSION) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function manualReentrancyAddLiquidityToBufferHook() external nonReentrant {
        BufferRouter(payable(this)).addLiquidityToBufferHook(IERC4626(address(0)), 0, 0, 0, address(0));
    }

    function manualReentrancyInitializeBufferHook() external nonReentrant {
        BufferRouter(payable(this)).initializeBufferHook(IERC4626(address(0)), 0, 0, 0, address(0));
    }
}
