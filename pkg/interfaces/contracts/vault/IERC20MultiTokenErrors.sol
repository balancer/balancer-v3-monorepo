// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IERC20MultiTokenErrors {
    /**
     * @notice The total supply of a pool token can't be lower than the absolute minimum.
     * @param totalSupply The total supply value that was below the minimum
     */
    error PoolTotalSupplyTooLow(uint256 totalSupply);
}
