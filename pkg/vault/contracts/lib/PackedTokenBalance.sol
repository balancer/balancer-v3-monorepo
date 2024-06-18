// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/**
 * @notice This library represents a data structure for packing a token's current raw and derived balances. A derived
 * balance can be the "last" live balance scaled18 of the raw token, or the balance of the wrapped version of the
 * token in a vault buffer, among others.
 *
 * @dev We could use a Solidity struct to pack balance values together in a single storage slot, but unfortunately
 * Solidity only allows for structs to live in either storage, calldata or memory. Because a memory struct still takes
 * up a slot in the stack (to store its memory location), and because the entire balance fits in a single stack slot
 * (two 128 bit values), using memory is strictly less gas performant. Therefore, we do manual packing and unpacking.
 *
 * We could also use custom types now, but given the simplicity here, and the existing EnumerableMap type, it seemed
 * easier to leave it as a bytes32.
 */
library PackedTokenBalance {
    // The 'rawBalance' portion of the balance is stored in the least significant 128 bits of a 256 bit word, while the
    // The 'derivedBalance' part uses the remaining 128 bits.
    uint256 private constant _MAX_BALANCE = 2 ** (128) - 1;

    /// @dev One of the balances is above the maximum value that can be stored.
    error BalanceOverflow();

    function getBalanceRaw(bytes32 balance) internal pure returns (uint256) {
        return uint256(balance) & _MAX_BALANCE;
    }

    function getBalanceDerived(bytes32 balance) internal pure returns (uint256) {
        return uint256(balance >> 128) & _MAX_BALANCE;
    }

    /// @dev Sets only the raw balance of balances and returns the new bytes32 balance
    function setBalanceRaw(bytes32 balance, uint256 newBalanceRaw) internal pure returns (bytes32) {
        return toPackedBalance(newBalanceRaw, getBalanceDerived(balance));
    }

    /// @dev Sets only the raw balance of balances and returns the new bytes32 balance
    function setBalanceDerived(bytes32 balance, uint256 newBalanceDerived) internal pure returns (bytes32) {
        return toPackedBalance(getBalanceRaw(balance), newBalanceDerived);
    }

    /// @dev Validates the size of `balanceRaw` and `balanceDerived`, then returns a packed balance bytes32.
    function toPackedBalance(uint256 balanceRaw, uint256 balanceDerived) internal pure returns (bytes32) {
        if (balanceRaw > _MAX_BALANCE || balanceDerived > _MAX_BALANCE) {
            revert BalanceOverflow();
        }

        return _pack(balanceRaw, balanceDerived);
    }

    /// @dev Decode and fetch both balances.
    function fromPackedBalance(bytes32 balance) internal pure returns (uint256 balanceRaw, uint256 balanceDerived) {
        return (getBalanceRaw(balance), getBalanceDerived(balance));
    }

    /// @dev Packs two uint128 values into a packed balance bytes32. It does not check balance sizes.
    function _pack(uint256 leastSignificant, uint256 mostSignificant) private pure returns (bytes32) {
        return bytes32((mostSignificant << 128) + leastSignificant);
    }
}
