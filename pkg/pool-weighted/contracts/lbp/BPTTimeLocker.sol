// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ERC6909Metadata } from "@openzeppelin/contracts/token/ERC6909/extensions/draft-ERC6909Metadata.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC6909 } from "@openzeppelin/contracts/token/ERC6909/draft-ERC6909.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";

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

    mapping(uint256 => uint256) internal _unlockTimestamps;

    /**
     * @notice Burn the locked tokens for the caller, and return the underlying BPT.
     * @param bptAddress The address of the BPT to burn
     */
    function burn(address bptAddress) public {
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

        _burn(msg.sender, id, amount);
        delete _unlockTimestamps[id];

        IERC20(address(uint160(id))).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Get the ID of the lock token, which is derived from the BPT address.
     * @param token The address of the token to lock
     * @return id The ID of the locked tokens
     */
    function getId(address token) public pure returns (uint256) {
        return uint256(uint160(address(token)));
    }

    /**
     * @notice Get the unlock timestamp for a given locked token ID.
     * @dev The owner can withdraw the underlying BPT at any time after this timestamp.
     * @param id The ID of the locked tokens, which is derived from the token address
     * @return unlockTimestamp The timestamp when the locked BPT can be withdrawn
     */
    function getUnlockTimestamp(uint256 id) external view returns (uint256) {
        return _unlockTimestamps[id];
    }

    /// @dev Locks an amount of tokens, locked amount is represented as an ERC6909 token.
    function _lockAmount(IERC20 token, address owner, uint256 amount, uint256 duration) internal {
        uint256 id = getId(address(token));

        // solhint-disable-next-line not-rely-on-time
        uint256 unlockTimestamp = block.timestamp + duration;

        IERC20Metadata tokenWithMetadata = IERC20Metadata(address(token));
        _setName(id, string(abi.encodePacked("Locked ", tokenWithMetadata.name())));
        _setSymbol(id, string(abi.encodePacked("LOCKED-", tokenWithMetadata.symbol())));
        _setDecimals(id, tokenWithMetadata.decimals());

        _unlockTimestamps[id] = unlockTimestamp;

        _mint(owner, id, amount);

        emit BPTTimelockSet(token, unlockTimestamp);
    }
}
