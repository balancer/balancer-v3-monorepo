// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

library BufferPackedTokenBalance {
    // The 'base' portion of the balance is stored in the least significant 128 bits of a 256 bit word, while the
    // 'wrapped' part uses the remaining 128 bits.

    uint256 private constant _MAX_BALANCE = 2 ** (128) - 1;

    /// @dev One of the balances is above the maximum value that can be stored.
    error BalanceOverflow();

    /// @dev Returns the amount of underlying tokens allocated in the Vault, in native decimal encoding.
    function getUnderlyingBalance(bytes32 balance) internal pure returns (uint256) {
        return uint256(balance) & _MAX_BALANCE;
    }

    /// @dev Returns the amount of wrapped tokens allocated in the Vault, in native decimal encoding.
    function getWrappedBalance(bytes32 balance) internal pure returns (uint256) {
        return uint256(balance >> 128) & _MAX_BALANCE;
    }

    /// @dev Updates underlying and wrapped balances and returns the new bytes32 balance
    function setBalances(
        bytes32,
        uint256 newUnderlyingBalance,
        uint256 newWrappedBalance
    ) internal pure returns (bytes32) {
        return toPackedBalance(newUnderlyingBalance, newWrappedBalance);
    }

    /// @dev Packs together `underlying` and `wrapped` amounts to create a balance value.
    function toPackedBalance(uint256 underlyingBalance, uint256 wrappedBalance) internal pure returns (bytes32) {
        if (underlyingBalance > _MAX_BALANCE || wrappedBalance > _MAX_BALANCE) {
            revert BalanceOverflow();
        }

        return _pack(underlyingBalance, wrappedBalance);
    }

    /// @dev Decode and fetch both balances.
    function fromPackedBalance(
        bytes32 balance
    ) internal pure returns (uint256 underlyingBalance, uint256 wrappedBalance) {
        return (getUnderlyingBalance(balance), getWrappedBalance(balance));
    }

    function hasLiquidity(bytes32 balance) internal pure returns (bool) {
        return getUnderlyingBalance(balance) > 0 || getWrappedBalance(balance) > 0;
    }

    /// @dev Packs two uint128 values into a bytes32.
    function _pack(uint256 leastSignificant, uint256 mostSignificant) private pure returns (bytes32) {
        return bytes32((mostSignificant << 128) + leastSignificant);
    }
}
