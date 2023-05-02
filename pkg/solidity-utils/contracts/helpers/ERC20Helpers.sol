// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IAsset.sol";

// solhint-disable

function _asIAsset(IERC20[] memory tokens) pure returns (IAsset[] memory assets) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
        assets := tokens
    }
}

function _sortTokens(
    IERC20 tokenA,
    IERC20 tokenB
) pure returns (IERC20[] memory tokens) {
    bool aFirst = tokenA < tokenB;
    IERC20[] memory sortedTokens = new IERC20[](2);

    sortedTokens[0] = aFirst ? tokenA : tokenB;
    sortedTokens[1] = aFirst ? tokenB : tokenA;

    return sortedTokens;
}

function _insertSorted(IERC20[] memory tokens, IERC20 token) pure returns (IERC20[] memory sorted) {
    sorted = new IERC20[](tokens.length + 1);

    if (tokens.length == 0) {
        sorted[0] = token;
        return sorted;
    }

    uint256 i;
    for (i = tokens.length; i > 0 && tokens[i - 1] > token; i--) sorted[i] = tokens[i - 1];
    for (uint256 j = 0; j < i; j++) sorted[j] = tokens[j];
    sorted[i] = token;
}

function _findTokenIndex(IERC20[] memory tokens, IERC20 token) pure returns (uint256) {
    // Note that while we know tokens are initially sorted, we cannot assume this will hold throughout
    // the pool's lifetime, as pools with mutable tokens can append and remove tokens in any order.
    uint256 tokensLength = tokens.length;
    for (uint256 i = 0; i < tokensLength; i++) {
        if (tokens[i] == token) {
            return i;
        }
    }

    _revert(Errors.INVALID_TOKEN);
}
