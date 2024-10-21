// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

contract ERC4626RateProvider is IRateProvider {
    IERC4626 private immutable _wrappedToken;

    constructor(IERC4626 wrappedToken) {
        _wrappedToken = wrappedToken;
    }

    /// @inheritdoc IRateProvider
    function getRate() external view override returns (uint256) {
        // `previewRedeem` calls `convertToAssets`, rounding down.
        return _wrappedToken.previewRedeem(FixedPoint.ONE);
    }
}
