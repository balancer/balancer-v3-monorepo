// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ERC6909Metadata } from "@openzeppelin/contracts/token/ERC6909/extensions/draft-ERC6909Metadata.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC6909 } from "@openzeppelin/contracts/token/ERC6909/draft-ERC6909.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";

/**
 * @notice Timelock for WeightedPool BPT created during an LBP migration.
 * @dev The migration router creates and initializes a new weighted pool upon completion of an LBP sale, sending the
 * BPT to this contract, and calls `_lockBPT` with an amount and lock duration (read from immutable LBP parameters)
 * to mint an amount of fungible ERC6909 tokens to the caller corresponding to the BPT amount, with an id that is the
 * numeric equivalent of the BPT address. After the timelock expires, a "lock token" holder can call `withdrawBPT` to
 * burn them and recover the original BPT.
 *
 * This contract uses ERC-6909, a token standard that allows a single smart contract to manage multiple fungible and
 * non-fungible tokens efficiently. ERC6909Metadata is an extension similar to ERC20Metadata that supports name,
 * symbol, and decimals.
 */
contract BPTTimeLocker is ERC6909, ERC6909Metadata, Multicall {
    using SafeERC20 for IERC20;

    /**
     * @notice Emitted when the unlock timestamp is set for a locked amount.
     * @dev The underlying BPT can be withdrawn when this timelock expires.
     * @param bptAddress The address of the locked BPT
     */
    event BPTTimelockSet(IERC20 indexed bptAddress, uint256 unlockTimestamp);

    /**
     * @notice The caller has a locked BPT balance, but is trying to burn it before the timelock expired.
     * @param unlockTimestamp The timestamp when the locked amount can be burned
     */
    error BPTStillLocked(uint256 unlockTimestamp);

    /// @notice The caller has no balance of the locked BPT.
    error NoLockedBPT();

    // The bptId is the numeric equivalent of the BPT address.
    mapping(uint256 bptId => uint256 unlockTimestamp) internal _unlockTimestamps;

    /**
     * @notice Withdraw the locked tokens for the caller, and return the underlying BPT.
     * @param bptAddress The address of the BPT to withdraw
     */
    function withdrawBPT(address bptAddress) public {
        uint256 id = getId(bptAddress);
        uint256 amount = balanceOf(msg.sender, id);
        if (amount == 0) {
            revert NoLockedBPT();
        }

        uint256 unlockTimestamp = _unlockTimestamps[id];
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp < unlockTimestamp) {
            revert BPTStillLocked(unlockTimestamp);
        }

        delete _unlockTimestamps[id];
        _burn(msg.sender, id, amount);

        IERC20(bptAddress).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Get the ID of the lock token, which is derived from the BPT address.
     * @param token The address of the token to lock
     * @return id The ID of the lock token representing the BPT
     */
    function getId(address token) public pure returns (uint256) {
        return uint256(uint160(address(token)));
    }

    /**
     * @notice Get the unlock timestamp for a given lock token ID.
     * @dev The owner can withdraw the underlying BPT at any time after this timestamp.
     * @param id The ID of the lock token, which is derived from the BPT address
     * @return unlockTimestamp The timestamp when the locked BPT can be withdrawn
     */
    function getUnlockTimestamp(uint256 id) external view returns (uint256) {
        return _unlockTimestamps[id];
    }

    /// @dev Locks an amount of tokens, locked amount is represented as an ERC6909 token.
    function _lockBPT(IERC20 bptAddress, address owner, uint256 amount, uint256 duration) internal {
        uint256 id = getId(address(bptAddress));

        // solhint-disable-next-line not-rely-on-time
        uint256 unlockTimestamp = block.timestamp + duration;

        IERC20Metadata tokenWithMetadata = IERC20Metadata(address(bptAddress));
        _setName(id, string(abi.encodePacked("Locked ", tokenWithMetadata.name())));
        _setSymbol(id, string(abi.encodePacked("LOCKED-", tokenWithMetadata.symbol())));
        _setDecimals(id, tokenWithMetadata.decimals());

        _unlockTimestamps[id] = unlockTimestamp;

        _mint(owner, id, amount);

        emit BPTTimelockSet(bptAddress, unlockTimestamp);
    }
}
