// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../AggRouter.sol";

contract AggRouterMock is AggRouter {
    constructor(IVault vault, IWETH weth, IPermit2 permit2) AggRouter(vault, weth, permit2) {}
}
