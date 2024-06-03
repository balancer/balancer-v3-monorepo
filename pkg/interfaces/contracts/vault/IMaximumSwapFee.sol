// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IMaximumSwapFee {
    /**
     * @notice Return the maximum swap fee for a pool.
     * @dev The Vault does not enforce bounds on swap fee percentages; it is up to the pools whether they want to
     * enforce minimum or maximum swap fees, by implementing the respective interfaces. The Vault will use this
     * interface if it is supported, as determined by the ERC-165 standard for checking whether interfaces are
     * supported. Though the minimum and maximum interfaces could be combined into something like
     * `ISwapFeePercentageBounds`, they are separate for maximum flexibility.
     */
    function getMaximumSwapFeePercentage() external view returns (uint256);
}
