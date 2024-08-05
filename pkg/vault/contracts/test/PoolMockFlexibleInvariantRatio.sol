// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "./PoolMock.sol";
import { BalancerPoolToken } from "../BalancerPoolToken.sol";

contract PoolMockFlexibleInvariantRatio is PoolMock {
    // Default min / max invariant ratio.
    uint256 private _minimumInvariantRatio = 0;
    uint256 private _maximumInvariantRatio = 1e6 * FixedPoint.ONE;

    constructor(IVault vault, string memory name, string memory symbol) PoolMock(vault, name, symbol) {
        // solhint-previous-line no-empty-blocks
    }

    function setMinimumInvariantRatio(uint256 minimumInvariantRatio) external {
        _minimumInvariantRatio = minimumInvariantRatio;
    }

    function getMinimumInvariantRatio() external view override returns (uint256) {
        return _minimumInvariantRatio;
    }

    function setMaximumInvariantRatio(uint256 maximumInvariantRatio) external {
        _maximumInvariantRatio = maximumInvariantRatio;
    }

    function getMaximumInvariantRatio() external view override returns (uint256) {
        return _maximumInvariantRatio;
    }
}
