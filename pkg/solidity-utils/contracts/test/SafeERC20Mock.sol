// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.0;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";

import "../openzeppelin/SafeERC20.sol";

contract SafeERC20Mock {
    using SafeERC20 for IERC20;

    constructor() {}

    function safeApprove(
        IERC20 token,
        address to,
        uint256 value
    ) external {
        token.safeApprove(to, value);
    }    
}
