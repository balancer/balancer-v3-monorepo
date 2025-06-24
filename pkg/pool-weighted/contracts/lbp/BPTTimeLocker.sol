// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ERC6909Metadata } from "@openzeppelin/contracts/token/ERC6909/extensions/draft-ERC6909Metadata.sol";
import { ERC6909 } from "@openzeppelin/contracts/token/ERC6909/draft-ERC6909.sol";
import { ERC6909ContentURI } from "@openzeppelin/contracts/token/ERC6909/extensions/draft-ERC6909ContentURI.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC6909 } from "@openzeppelin/contracts/interfaces/draft-IERC6909.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ILBPool, LBPoolImmutableData } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import {
    TokenConfig,
    RemoveLiquidityParams,
    RemoveLiquidityKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import {
    BalancerContractRegistry,
    ContractType
} from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";

import { WeightedPoolFactory } from "../WeightedPoolFactory.sol";

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract BPTTimeLocker is ERC6909, ERC6909Metadata, Multicall {
    using SafeERC20 for IERC20;

    /**
     * @dev Emitted when the unlock timestamp is set for a locked amount.
     * @param id The ID of the locked tokens, which is derived from the token address
     */
    event SetUnlockTimestamp(uint256 indexed id, uint256 unlockTimestamp);

    /**
     * @dev Amount is not unlocked yet.
     * @param unlockTimestamp The timestamp when the locked amount can be unlocked
     */
    error AmountNotUnlockedYet(uint256 unlockTimestamp);

    /// @dev The amount to burn is not locked.
    error NoLockedAmount();

    mapping(uint256 => uint256) internal _unlockTimestamps;

    /**
     * @notice Burn the locked tokens for the caller.
     * @param bptAddress The address of the BPT to burn
     */
    function burn(address bptAddress) public {
        uint256 id = getId(bptAddress);
        uint256 amount = balanceOf(msg.sender, id);
        if (amount == 0) {
            revert NoLockedAmount();
        }

        uint256 unlockTimestamp = _unlockTimestamps[id];
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp < unlockTimestamp) {
            revert AmountNotUnlockedYet(unlockTimestamp);
        }

        _burn(msg.sender, id, amount);
        delete _unlockTimestamps[id];

        IERC20(address(uint160(id))).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Get the ID of the locked tokens, which is derived from the token address.
     * @param token The address of the token to lock
     * @return id The ID of the locked tokens
     */
    function getId(address token) public pure returns (uint256) {
        return uint256(uint160(address(token)));
    }

    /**
     * @notice Get the unlock timestamp for a given locked token ID.
     * @param id The ID of the locked tokens, which is derived from the token address
     * @return unlockTimestamp The timestamp when the locked amount can be unlocked
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

        emit SetUnlockTimestamp(id, unlockTimestamp);
    }
}
