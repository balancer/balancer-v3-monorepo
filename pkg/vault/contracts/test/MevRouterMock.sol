// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { MevRouter } from "../MevRouter.sol";

string constant MOCK_MEV_ROUTER_VERSION = "Mock Router v1";

contract MevRouterMock is MevRouter {
    error MockErrorCode();

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2,
        MevRouterParams memory params
    ) MevRouter(vault, weth, permit2, MOCK_MEV_ROUTER_VERSION, params) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
