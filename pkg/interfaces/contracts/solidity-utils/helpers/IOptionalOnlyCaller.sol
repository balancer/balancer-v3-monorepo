// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.7.0 <0.9.0;

/**
 * @dev Interface for the OptionalOnlyCaller helper, used to opt in to a caller
 * verification for a given address to methods that are otherwise callable by any address.
 */
interface IOptionalOnlyCaller {
    /**
     * @dev Emitted every time setOnlyCallerCheck is called.
     */
    event OnlyCallerOptIn(address user, bool enabled);

    /**
     * @dev Enables / disables verification mechanism for caller.
     * @param enabled - True if caller verification shall be enabled, false otherwise.
     */
    function setOnlyCallerCheck(bool enabled) external;

    function setOnlyCallerCheckWithSignature(address user, bool enabled, bytes memory signature) external;

    /**
     * @dev Returns true if caller verification is enabled for the given user, false otherwise.
     */
    function isOnlyCallerEnabled(address user) external view returns (bool);
}
