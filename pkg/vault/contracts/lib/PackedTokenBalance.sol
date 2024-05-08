// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/** TODO refactor
 * @notice This library represents a data structure for packing a token's current raw and derived balances. A derived
 * balance can be the "last" live balance scaled18 of the raw token, or the balance of the wrapped version of the
 * token in a vault buffer, among others.
 *
 * @dev `rawBalance` represents the actual number of tokens in the Vault allocated to the pool, in native decimal
 * encoding. `lastLiveBalanceScaled18` represents the "last live" balance, which is stored as an 18-decimal floating
 * point value so that it can be conveniently compared to other scaled values.
 *
 * "Last" refers to the final live balance as of the last time the raw balance changed (e.g., after a swap or liquidity
 * operation). The "live" balance is the balance presented to the Pool in hooks: with any applicable decimal and
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
    // 'derivedBalance' part uses the remaining 128 bits.

    uint256 private constant _MAX_BALANCE = 2 ** (128) - 1;

    /// @dev One of the balances is above the maximum value that can be stored.
    error BalanceOverflow();

    /// @dev TODO comment
    function getBalanceRaw(bytes32 balance) internal pure returns (uint256) {
        return uint256(balance) & _MAX_BALANCE;
    }

    /// @dev TODO comment
    function getBalanceDerived(bytes32 balance) internal pure returns (uint256) {
        return uint256(balance >> 128) & _MAX_BALANCE;
    }

    /// @dev TODO comment
    function setBalances(
        bytes32 balance,
        uint256 newBalanceRaw,
        uint256 newBalanceDerived
    ) internal pure returns (bytes32) {
        return toPackedBalance(newBalanceRaw, newBalanceDerived);
    }

    function setBalanceRaw(bytes32 balance, uint256 newBalanceRaw) internal pure returns (bytes32) {
        return toPackedBalance(newBalanceRaw, getBalanceDerived(balance));
    }

    /// @dev TODO comment
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

    /// @dev Packs two uint128 values into a bytes32.
    function _pack(uint256 leastSignificant, uint256 mostSignificant) private pure returns (bytes32) {
        return bytes32((mostSignificant << 128) + leastSignificant);
    }
}
