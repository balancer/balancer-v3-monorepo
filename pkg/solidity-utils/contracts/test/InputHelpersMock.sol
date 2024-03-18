// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.20;

import "../helpers/InputHelpers.sol";

contract InputHelpersMock {
    function sortTokens(IERC20[] memory tokens) external pure returns (IERC20[] memory) {
        return InputHelpers.sortTokens(tokens);
    }

    function ensureSortedTokens(IERC20[] memory tokens) external pure {
        InputHelpers.ensureSortedTokens(tokens);
    }
}
