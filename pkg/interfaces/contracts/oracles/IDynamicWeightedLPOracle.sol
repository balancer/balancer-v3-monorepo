// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IWeightedLPOracle } from "./IWeightedLPOracle.sol";

/**
 * @notice Interface for dynamic weighted LP oracles.
 * @dev Extends IWeightedLPOracle with no additional methods, as the dynamic behavior
 * is implemented through overriding internal methods in the implementation.
 */
interface IDynamicWeightedLPOracle is IWeightedLPOracle {
    // No additional methods needed - dynamic behavior is internal implementation detail
}