// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IVaultExtensionMock {
    function manualPausePool(address pool) external;

    function manualUnpausePool(address pool) external;

    function manualEnableRecoveryMode(address pool) external;

    function manualDisableRecoveryMode(address pool) external;

    // Used in tests to circumvent minimum swap fees.
    function manuallySetSwapFee(address pool, uint256 swapFeePercentage) external;
}
