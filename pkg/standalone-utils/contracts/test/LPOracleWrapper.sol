// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @dev latestRoundData is a view function, so we can't measure the gas cost of calling it on hardhat.
 * So, we need a non-view function to measure the gas. This wrapper implements this non-view function.
 */
contract LPOracleWrapper {
    address private oracle;
    // State used only to justify the non-view function.
    uint256 private dummy;

    constructor(address _oracle) {
        oracle = _oracle;
    }

    function callLatestRoundData() external returns (uint80, int256, uint256, uint256, uint80) {
        // This function must be a non-view function to measure the gas cost of calling it on hardhat.
        // Since `solhint-disable func-mutability` does not work when compiling with hardhat, we modify
        // a dummy state to allow this function to be a non-view.
        dummy = block.timestamp;

        return AggregatorV3Interface(oracle).latestRoundData();
    }
}
