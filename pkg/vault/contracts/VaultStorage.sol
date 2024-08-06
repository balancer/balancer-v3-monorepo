// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StorageSlotExtension } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";
import {
    TransientStorageHelpers,
    AddressArraySlotType,
    TokenDeltaMappingSlotType
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

import { VaultStateBits } from "./lib/VaultStateLib.sol";
import { PoolConfigBits } from "./lib/PoolConfigLib.sol";

// solhint-disable max-states-count

/**
 * @notice Storage layout for the Vault.
 * @dev This contract has no code, but is inherited by all three Vault contracts. In order to ensure that *only* the
 * Vault contract's storage is actually used, calls to the extension contracts must be delegate calls made through the
 * main Vault.
 */
contract VaultStorage {
    using StorageSlotExtension for *;

    /***************************************************************************
                                     Constants
    ***************************************************************************/

    // Pools can have between two and eight tokens.
    uint256 internal constant _MIN_TOKENS = 2;
    // This maximum token count is also implicitly hard-coded in `PoolConfigLib` (through packing `tokenDecimalDiffs`).
    uint256 internal constant _MAX_TOKENS = 8;

    // Minimum BPT amount minted upon initialization.
    uint256 internal constant _MINIMUM_BPT = 1e6;

    // Minimum given amount to wrap/unwrap (applied to native decimal values), to avoid rounding issues.
    uint256 internal constant _MINIMUM_WRAP_AMOUNT = 1e3;

    // Minimum swap amount (applied to scaled18 values), enforced as a security measure to block potential
    // exploitation of rounding errors
    uint256 internal constant _MINIMUM_TRADE_AMOUNT = 1e6;

    // Maximum pause and buffer period durations.
    uint256 internal constant _MAX_PAUSE_WINDOW_DURATION = 356 days * 4;
    uint256 internal constant _MAX_BUFFER_PERIOD_DURATION = 90 days;

    /***************************************************************************
                          Transient Storage Declarations
    ***************************************************************************/

    // NOTE: If you use a constant, then it is simply replaced everywhere when this constant is used
    // by what is written after =. If you use immutable, the value is first calculated and
    // then replaced everywhere. That means that if a constant has executable variables,
    // they will be executed every time the constant is used.

    // solhint-disable var-name-mixedcase
    bytes32 private immutable _IS_UNLOCKED_SLOT = _calculateVaultStorageSlot("isUnlocked");
    bytes32 private immutable _NON_ZERO_DELTA_COUNT_SLOT = _calculateVaultStorageSlot("nonZeroDeltaCount");
    bytes32 private immutable _TOKEN_DELTAS_SLOT = _calculateVaultStorageSlot("tokenDeltas");
    // solhint-enable var-name-mixedcase

    /***************************************************************************
                                    Pool State
    ***************************************************************************/

    // Pool -> PoolConfig (fees, pause window, configuration flags).
    mapping(address => PoolConfigBits) internal _poolConfigBits;

    // Pool -> PoolRoleAccounts (accounts assigned to specific roles; e.g., pauseManager).
    mapping(address => PoolRoleAccounts) internal _poolRoleAccounts;

    // Pool -> roleId (corresponding to a particular function) -> PoolFunctionPermission.
    mapping(address => mapping(bytes32 => PoolFunctionPermission)) internal _poolFunctionPermissions;

    // Pool -> hooks contracts.
    mapping(address => IHooks) internal _hooksContracts;

    // Pool -> set of tokens.
    mapping(address => IERC20[]) internal _poolTokens;

    // Pool -> (token -> TokenInfo): The token configuration of each Pool's tokens.
    mapping(address => mapping(IERC20 => TokenInfo)) internal _poolTokenInfo;

    // Pool -> (token -> PackedTokenBalance): structure containing the current raw and "last live" scaled balances.
    // Last live balances are used for yield fee computation, and since these have rates applied, they are stored
    // as scaled 18-decimal FP values. Each value takes up half the storage slot (i.e., 128 bits).
    mapping(address => mapping(uint256 => bytes32)) internal _poolTokenBalances;

    // Pool -> (Token -> fee): aggregate protocol swap/yield fees accumulated in the Vault for harvest.
    // Reusing PackedTokenBalance to save bytecode (despite differing semantics).
    // It's arbitrary which is which: we define raw = swap; derived = yield.
    mapping(address => mapping(IERC20 => bytes32)) internal _aggregateFeeAmounts;

    /***************************************************************************
                                    Vault State
    ***************************************************************************/

    // The Pause Window and Buffer Period are timestamp-based: they should not be relied upon for sub-minute accuracy.
    uint32 internal immutable _vaultPauseWindowEndTime;
    uint32 internal immutable _vaultBufferPeriodEndTime;

    // Stored as a convenience, to avoid calculating it on every operation.
    uint32 internal immutable _vaultBufferPeriodDuration;

    // Bytes32 with pause flags for the Vault, buffers, and queries.
    VaultStateBits internal _vaultStateBits;

    /**
     * @dev Represents the total reserve of each ERC20 token. It should be always equal to `token.balanceOf(vault)`,
     * except during `unlock`.
     */
    mapping(IERC20 => uint256) internal _reservesOf;

    /***************************************************************************
                                Contract References
    ***************************************************************************/

    // Upgradeable contract in charge of setting permissions.
    IAuthorizer internal _authorizer;

    // Contract that receives aggregate swap and yield fees.
    IProtocolFeeController internal _protocolFeeController;

    /***************************************************************************
                                  ERC4626 Buffers
    ***************************************************************************/

    // Any ERC4626 token can trade using a buffer, which is like a pool, but internal to the Vault.
    // The registry key is the wrapped token address, so there can only ever be one buffer per wrapped token.
    // This means they are permissionless, and have no registration function.
    //
    // Anyone can add liquidity to a buffer

    // A buffer will only ever have two tokens: wrapped and underlying. We pack the wrapped and underlying balances
    // into a single bytes32, interpreted with the `PackedTokenBalance` library.

    // ERC4626 token address -> PackedTokenBalance, which stores both the underlying and wrapped token balances.
    // Reusing PackedTokenBalance to save bytecode (despite differing semantics).
    // It's arbitrary which is which: we define raw = underlying token; derived = wrapped token.
    mapping(IERC4626 => bytes32) internal _bufferTokenBalances;

    // The LP balances for buffers. LP balances are not tokenized (i.e., represented by ERC20 tokens like BPT), but
    // rather accounted for within the Vault.

    // Wrapped token address -> user address -> LP balance.
    mapping(IERC4626 => mapping(address => uint256)) internal _bufferLpShares;

    // Total LP shares.
    mapping(IERC4626 => uint256) internal _bufferTotalShares;

    // Prevents a malicious ERC4626 from changing the asset after the buffer was initialized.
    mapping(IERC4626 => address) internal _bufferAssets;

    /***************************************************************************
                             Transient Storage Access
    ***************************************************************************/

    function _isUnlocked() internal view returns (StorageSlotExtension.BooleanSlotType slot) {
        return _IS_UNLOCKED_SLOT.asBoolean();
    }

    function _nonZeroDeltaCount() internal view returns (StorageSlotExtension.Uint256SlotType slot) {
        return _NON_ZERO_DELTA_COUNT_SLOT.asUint256();
    }

    function _tokenDeltas() internal view returns (TokenDeltaMappingSlotType slot) {
        return TokenDeltaMappingSlotType.wrap(_TOKEN_DELTAS_SLOT);
    }

    function _calculateVaultStorageSlot(string memory key) private pure returns (bytes32) {
        return TransientStorageHelpers.calculateSlot(type(VaultStorage).name, key);
    }
}
