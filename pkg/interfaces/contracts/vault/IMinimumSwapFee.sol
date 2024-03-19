// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IMinimumSwapFee {
    /**
     * @notice Return the minimum swap fee for a pool.
     * @dev The Vault imposes a universal maximum swap fee - but not a minimum.
     * Pool types wishing to implement a minimum can implement this interface. The Vault will use this interface
     * if it is supported, as determined by the ERC-165 standard for checking whether interfaces are supported.
     */
    function getMinimumSwapFeePercentage() external view returns (uint256);
}
