// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

/**
 * @notice This library represents a data structure for packing a token's current raw and "last" live Pool balances.
 * @dev `rawBalance` represents the actual number of tokens in the Vault allocated to the pool, in native decimal
 * encoding. `lastLiveBalanceScaled18` represents the "last live" balance, which is stored as an 18-decimal floating
 * point value so that it can be conveniently compared to other scaled values.
 *
 * "Last" refers to the final live balance as of the last time the raw balance changed (e.g., after a swap or liquidity
 * operation). The "live" balance is the balance presented to the Pool in callbacks: with any applicable decimal and
 * rate scaling applied, and any applicable protocol fees (swap and yield) deducted.
 *
 * We could use a Solidity struct to pack these three values together in a single storage slot, but unfortunately
 * Solidity only allows for structs to live in either storage, calldata or memory. Because a memory struct still takes
 * up a slot in the stack (to store its memory location), and because the entire balance fits in a single stack slot
 * (two 128 bit values), using memory is strictly less gas performant. Therefore, we do manual packing and unpacking.
 *
 * We could also use custom types now, but given the simplicity here, and the existing EnumerableMap type, it seemed
 * easier to leave it as a bytes32.
 */
library PackedTokenBalance {
    // The 'rawBalance' portion of the balance is stored in the least significant 128 bits of a 256 bit word, while the
    // 'lastLiveBalanceScaled18' part uses the remaining 128 bits.

    uint256 private constant _MAX_BALANCE = 2 ** (128) - 1;

    /// @dev One of the balances is above the maximum value that can be stored.
    error BalanceOverflow();

    /// @dev Returns the amount of Pool tokens allocated in the Vault, in native decimal encoding.
    function getRawBalance(bytes32 balance) internal pure returns (uint256) {
        return uint256(balance) & _MAX_BALANCE;
    }

    /// @dev Returns the last live Pool balance, as an 18-decimal floating point number.
    function getLastLiveBalanceScaled18(bytes32 balance) internal pure returns (uint256) {
        return uint256(balance >> 128) & _MAX_BALANCE;
    }

    /// @dev Replace a raw balance value, without modifying the live balance.
    function setRawBalance(bytes32 balance, uint256 newRawBalance) internal pure returns (bytes32) {
        return toPackedBalance(newRawBalance, getLastLiveBalanceScaled18(balance));
    }

    /// @dev Replace a raw balance value, without modifying the live balance.
    function setLastLiveBalanceScaled18(bytes32 balance, uint256 newLastLiveBalance) internal pure returns (bytes32) {
        return toPackedBalance(getRawBalance(balance), newLastLiveBalance);
    }

    /// @dev Packs together `rawBalance` and `lastLiveBalanceScaled18` amounts to create a balance value.
    function toPackedBalance(uint256 balanceRaw, uint256 balanceLastLiveScaled18) internal pure returns (bytes32) {
        if (balanceRaw > _MAX_BALANCE || balanceLastLiveScaled18 > _MAX_BALANCE) {
            revert BalanceOverflow();
        }

        return _pack(balanceRaw, balanceLastLiveScaled18);
    }

    /// @dev Decode and fetch both balances.
    function fromPackedBalance(
        bytes32 balance
    ) internal pure returns (uint256 balanceRaw, uint256 balanceLastLiveScaled18) {
        return (getRawBalance(balance), getLastLiveBalanceScaled18(balance));
    }

    /// @dev Packs two uint128 values into a bytes32.
    function _pack(uint256 leastSignificant, uint256 mostSignificant) private pure returns (bytes32) {
        return bytes32((mostSignificant << 128) + leastSignificant);
    }
}
