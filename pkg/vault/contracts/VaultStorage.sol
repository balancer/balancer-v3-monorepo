// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

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

    // Minimum given amount to wrap/unwrap, to avoid rounding issues
    uint256 internal constant _MINIMUM_WRAP_AMOUNT = 1e6;

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

    // Maximum pause and buffer period durations.
    uint256 internal constant _MAX_PAUSE_WINDOW_DURATION = 356 days * 4;
    uint256 internal constant _MAX_BUFFER_PERIOD_DURATION = 90 days;

    // When wrapping/unwrapping an IERC4626, the actual operation can return a different result from convertToAssets
    // and convertToShares. _MAX_CONVERT_ERROR is the maximum tolerance to convert errors.
    uint256 internal constant _MAX_CONVERT_ERROR = 2;

    // Code extension for Vault.
    IVaultExtension internal immutable _vaultExtension;

    // Registry of numeric pool states.
    mapping(address => PoolConfigBits) internal _poolState;

    // Registry of pool flags.
    mapping(address => PoolFlags) internal _poolFlags;

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
     * @notice Represents the total reserve of each ERC20 token.
     * @dev It should be always equal to `token.balanceOf(vault)`, except during `lock`.
     */
    mapping(IERC20 => uint256) internal _reservesOf;

    // Pool -> (Token -> fee): Protocol fees (from both swap and yield) accumulated in the Vault for harvest.
    mapping(address => mapping(IERC20 => uint256)) internal _protocolFees;

    // Pool -> (Token -> fee): pool creator fees (from swap) accumulated in the Vault for harvest.
    mapping(address => mapping(IERC20 => uint256)) internal _poolCreatorFees;

    // Upgradeable contract in charge of setting permissions.
    IAuthorizer internal _authorizer;

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

    function _isUnlocked() internal pure returns (StorageSlot.BooleanSlotType slot) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            slot := __isUnlocked.slot
        }
    }

    function _nonzeroDeltaCount() internal pure returns (StorageSlot.Uint256SlotType slot) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            slot := __nonzeroDeltaCount.slot
        }
    }

    function _tokenDeltas() internal pure returns (TokenDeltaMappingSlotType slot) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            slot := __tokenDeltas.slot
        }
    }

    // Buffers are a vault internal concept, keyed on the wrapped token address.
    // There will only ever be one buffer per wrapped token. This also means they are permissionless and
    // have no registration function. You can always add liquidity to a buffer.

    // A buffer will only ever have two tokens: wrapped and underlying
    // we pack the wrapped and underlying balance into a single bytes32
    // wrapped token address -> PackedTokenBalance
    mapping(IERC20 => bytes32) internal _bufferTokenBalances;

    // The LP balances for buffers. To start, LP balances will not be represented as ERC20 shares.
    // If we end up with a need to incentivize buffers, we can wrap this in an ERC20 wrapper without
    // introducing more complexity to the vault.
    // wrapped token address -> user address -> LP balance
    mapping(IERC20 => mapping(address => uint256)) internal _bufferLpShares;
    // total LP shares
    mapping(IERC20 => uint256) internal _bufferTotalShares;

    // Prevents a malicious ERC4626 from changing the asset after the buffer was initialized.
    mapping(IERC20 => address) internal _bufferAssets;
}
