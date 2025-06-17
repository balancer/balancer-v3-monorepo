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
import { ITimelock } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ITimelock.sol";
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

contract Timelock is ERC6909, ERC6909Metadata, Multicall {
    using SafeERC20 for IERC20;

    event SetUnlockTimestamp(uint256 indexed id, uint256 unlockTimestamp);

    error TimeLockedAmountNotUnlockedYet(uint256 id, uint256 unlockTimestamp);

    mapping(uint256 => uint256) private _unlockTimestamps;

    function burn(uint256 id) public {
        uint256 amount = balanceOf(msg.sender, id);
        if (amount == 0) {
            return;
        }

        uint256 unlockTimestamp = _unlockTimestamps[id];
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp < unlockTimestamp) {
            revert TimeLockedAmountNotUnlockedYet(id, unlockTimestamp);
        }

        _burn(msg.sender, id, amount);
        delete _unlockTimestamps[id];
    }

    function _lockAmount(IERC20 token, address owner, uint256 amount, uint256 duration) internal {
        uint256 id = uint256(uint160(address(token)));

        // solhint-disable-next-line not-rely-on-time
        uint256 unlockTimestamp = block.timestamp + duration;

        IERC20Metadata tokenWithMetadata = IERC20Metadata(address(token));
        _setName(uint256(uint160(owner)), string(abi.encodePacked("Locked ", tokenWithMetadata.name())));
        _setSymbol(uint256(uint160(owner)), string(abi.encodePacked("L-", tokenWithMetadata.symbol())));
        _setDecimals(uint256(uint160(owner)), tokenWithMetadata.decimals());

        _unlockTimestamps[id] = unlockTimestamp;

        _mint(owner, id, amount);

        emit SetUnlockTimestamp(id, unlockTimestamp);
    }
}
