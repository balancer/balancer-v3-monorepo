// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Interface for wrapped Balancer pool tokens
interface IWrappedBalancerPoolToken {
    /// @notice The vault is unlocked
    error VaultIsUnlocked();

    /**
     * @notice Mints wrapped BPTs in exchange for locked BPTs
     * @param amount The amount of locked BPTs to exchange for wrapped BPTs
     */
    function mint(uint256 amount) external;

    /**
     * @notice Burns wrapped BPTs to unlock the underlying locked BPTs
     * @param value The amount of wrapped BPTs to burn in order to unlock locked BPTs
     */
    function burn(uint256 value) external;

    /**
     * @notice Burns wrapped BPTs on behalf of an approved account to unlock their locked BPTs
     * @param account The address from which the wrapped BPTs will be burned
     * @param value The amount of wrapped BPTs to burn in order to unlock locked BPTs
     */
    function burnFrom(address account, uint256 value) external;
}
