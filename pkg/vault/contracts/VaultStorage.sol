// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { PoolFunctionPermission, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";
import { StorageSlot } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlot.sol";
import {
    AddressArraySlotType,
    TokenDeltaMappingSlotType
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

import { VaultStateBits } from "./lib/VaultStateLib.sol";
import { PoolConfigBits } from "./lib/PoolConfigLib.sol";

// solhint-disable max-states-count

/**
 * @dev Storage layout for Vault. This contract has no code other than a thin abstraction for transient storage slots.
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

    /// @notice Global lock state. Unlock to operate with the vault.
    bool private __isUnlocked;

    /**
     * @notice The total number of nonzero deltas over all active + completed lockers.
     * @dev It is non-zero only during `lock` calls.
     */
    uint256 private __nonzeroDeltaCount;

    /**
     * @notice Represents the token due/owed during an operation.
     * @dev Must all net to zero when the operation is finished.
     */
    mapping(IERC20 => int256) private __tokenDeltas;

    /**
     * @dev The aggregate fee percentage charged on swaps, composed of both the protocol swap fee and creator fee.
     * It is given by: protocolSwapFeePct + (1 - protocolSwapFeePct) * poolCreatorFeePct (see derivation in TODO).
     * This will not change during the operation, so cache it in transient storage.
     */
    uint256 private __aggregateProtocolSwapFeePercentage;

    /**
     * @dev Transient storage of the current protocol swap and yield fee percentages (packed into one slot).
     * This will not change during the operation, and is used to detect whether we need to force collection of
     * protocol fees on a given pool before charging "new" fees.
     */
    bytes32 private __currentProtocolFeePercentages;

    /**
     * @dev Pool -> Packed bytes32 with current protocol swap and yield fees.
     * Store the protocol swap and yield fee percentages the last time fees were charged. This is because separation
     * of protocol and creator fees is deferred until collection, and the protocol fee percentages might have changed
     * between these times. To avoid retroactive changes, we would ideally force collection of fees before updating
     * the fee percentage.
     *
     * This is fine for pool creator fees, but we cannot force collection on all pools when the protocol swap fee
     * changes. So we always collect fees based on the "last" value of the percentages. If we are about to charge
     * protocol fees and notice the percentages have change, force collection of that pool first, then update the
     * "last" values (i.e., lazy evaluation to ensure the rates on collection are the same as when the fees were
     * incurred).
     */
    mapping(address => bytes32) private _lastProtocolFeePercentages;

    // Pool -> (Token -> fee): protocol fees (swap and creator) accumulated in the Vault for harvest.
    mapping(address => EnumerableMap.IERC20ToUint256Map) internal _protocolSwapFees;

    // Token -> fee: Protocol yield fees accumulated in the Vault for harvest.
    mapping(address => EnumerableMap.IERC20ToUint256Map) internal _protocolYieldFees;

    /**
     * @dev Represents the total reserve of each ERC20 token. It should be always equal to `token.balanceOf(vault)`,
     * except during `lock`.
     */
    mapping(IERC20 => uint256) internal _reservesOf;

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

    // Bytes32 with protocol fees and paused flags.
    VaultStateBits internal _vaultState;

    // pool -> roleId (corresponding to a particular function) -> PoolFunctionPermission.
    mapping(address => mapping(bytes32 => PoolFunctionPermission)) internal _poolFunctionPermissions;

    // pool -> PoolRoleAccounts (accounts assigned to specific roles; e.g., pauseManager).
    mapping(address => PoolRoleAccounts) internal _poolRoleAccounts;

    // solhint-disable no-inline-assembly

    function _isUnlocked() internal pure returns (StorageSlot.BooleanSlotType slot) {
        assembly {
            slot := __isUnlocked.slot
        }
    }

    function _nonzeroDeltaCount() internal pure returns (StorageSlot.Uint256SlotType slot) {
        assembly {
            slot := __nonzeroDeltaCount.slot
        }
    }

    function _tokenDeltas() internal pure returns (TokenDeltaMappingSlotType slot) {
        assembly {
            slot := __tokenDeltas.slot
        }
    }

    function _aggregateProtocolSwapFeePercentage() internal pure returns (StorageSlot.Uint256SlotType slot) {
        assembly {
            slot := __aggregateProtocolSwapFeePercentage.slot
        }
    }

    function _currentProtocolFeePercentages() internal pure returns (StorageSlot.Bytes32SlotType slot) {
        assembly {
            slot := __currentProtocolFeePercentages.slot
        }
    }
}
