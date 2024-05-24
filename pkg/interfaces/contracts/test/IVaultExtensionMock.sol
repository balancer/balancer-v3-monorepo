// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IVaultExtensionMock {
    // Used in tests to circumvent minimum swap fees.
    function manuallySetSwapFee(address pool, uint256 swapFeePercentage) external;
}
