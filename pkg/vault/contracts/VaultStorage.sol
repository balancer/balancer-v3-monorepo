// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";

import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";

import { VaultStateBits } from "./lib/VaultStateLib.sol";
import { PoolConfigBits } from "./lib/PoolConfigLib.sol";

// solhint-disable max-states-count

/**
 * @dev Storage layout for Vault. This contract has no code.
 */
contract VaultStorage {
    // Minimum BPT amount minted upon initialization.
    uint256 internal constant _MINIMUM_BPT = 1e6;

    // Pools can have two, three, or four tokens.
    uint256 internal constant _MIN_TOKENS = 2;
    // This maximum token count is also hard-coded in `PoolConfigLib`.
    uint256 internal constant _MAX_TOKENS = 4;

    // Maximum protocol swap fee percentage. 1e18 corresponds to a 100% fee.
    uint256 internal constant _MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50e16; // 50%

    // Maximum protocol yield fee percentage.
    // TODO Optimize storage; could pack fees into one slot (potentially a single vaultState slot).
    uint256 internal constant _MAX_PROTOCOL_YIELD_FEE_PERCENTAGE = 20e16; // 20%

    // Maximum pool swap fee percentage.
    uint256 internal constant _MAX_SWAP_FEE_PERCENTAGE = 10e16; // 10%

    // Code extension for Vault.
    IVaultExtension internal immutable _vaultExtension;

    // Registry of pool configs.
    mapping(address => PoolConfigBits) internal _poolConfig;

    // Store pool pause managers.
    mapping(address => address) internal _poolPauseManagers;

    // Pool -> (token -> PackedTokenBalance): structure containing the current raw and "last live" scaled balances.
    // Last live balances are used for yield fee computation, and since these have rates applied, they are stored
    // as scaled 18-decimal FP values. Each value takes up half the storage slot (i.e., 128 bits).
    mapping(address => EnumerableMap.IERC20ToBytes32Map) internal _poolTokenBalances;

    // Pool -> (token -> TokenConfig): The token configuration of each Pool's tokens.
    mapping(address => mapping(IERC20 => TokenConfig)) internal _poolTokenConfig;

    /// @notice List of lockers. It is empty except during `lock` calls.
    address[] internal _lockers;

    /**
     * @notice The total number of nonzero deltas over all active + completed lockers.
     * @dev It is non-zero only during `lock` calls.
     */
    uint256 internal _nonzeroDeltaCount;

    /**
     * @notice Represents the token due/owed to each locker.
     * @dev Must all net to zero when the last locker is released.
     */
    mapping(address => mapping(IERC20 => int256)) internal _tokenDeltas;

    /**
     * @notice Represents the total reserve of each ERC20 token.
     * @dev It should be always equal to `token.balanceOf(vault)`, except during `lock`.
     */
    mapping(IERC20 => uint256) internal _reservesOf;

    // Token -> fee: Protocol fees (from both swap and yield) accumulated in the Vault for harvest.
    mapping(IERC20 => uint256) internal _protocolFees;

    // Upgradeable contract in charge of setting permissions.
    IAuthorizer internal _authorizer;

    uint256 public constant MAX_PAUSE_WINDOW_DURATION = 356 days * 4;
    uint256 public constant MAX_BUFFER_PERIOD_DURATION = 90 days;

    // The Pause Window and Buffer Period are timestamp-based: they should not be relied upon for sub-minute accuracy.
    // solhint-disable not-rely-on-time

    uint256 internal immutable _vaultPauseWindowEndTime;
    uint256 internal immutable _vaultBufferPeriodEndTime;
    // Stored as a convenience, to avoid calculating it on every operation.
    uint256 internal immutable _vaultBufferPeriodDuration;

    // Bytes32 with protocol fees and paused flags
    VaultStateBits internal _vaultState;
}
