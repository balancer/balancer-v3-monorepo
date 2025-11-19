// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../lib/MinTokenBalanceLib.sol";

contract MinTokenBalanceLibMock {
    function validateMinimumTokenBalances(
        TokenConfig[] memory tokens,
        uint256[] memory minTokenBalances
    ) external view returns (uint256[] memory) {
        return MinTokenBalanceLib.validateMinimumTokenBalances(tokens, minTokenBalances);
    }
}
