// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IECLPSurgeHook {
    /**
     * @notice The rotation angle is too small or too large for the surge hook to be used.
     * @dev The surge hook accept angles from 30 to 60 degrees. Outside of this range, the computation of the peak
     * price cannot be approximated by sine/cosine.
     */
    error InvalidRotationAngleForSurgeHook();
}
