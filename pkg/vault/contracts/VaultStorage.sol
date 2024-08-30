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

    // Maximum pause and buffer period durations.
    uint256 internal constant _MAX_PAUSE_WINDOW_DURATION = 365 days * 4;
    uint256 internal constant _MAX_BUFFER_PERIOD_DURATION = 90 days;

    // Minimum given amount to wrap/unwrap (applied to native decimal values), to avoid rounding issues.
    uint256 internal constant _MINIMUM_WRAP_AMOUNT = 1e3;

    // Minimum BPT amount minted upon initialization.
    uint256 internal constant _BUFFER_MINIMUM_TOTAL_SUPPLY = 1e4;

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

    // Pool-specific configuration data (e.g., fees, pause window, configuration flags).
    mapping(address pool => PoolConfigBits poolConfig) internal _poolConfigBits;

    // Accounts assigned to specific roles; e.g., pauseManager, swapManager.
    mapping(address pool => PoolRoleAccounts roleAccounts) internal _poolRoleAccounts;

    // The hooks contracts associated with each pool.
    mapping(address pool => IHooks hooksContract) internal _hooksContracts;

    // The set of tokens associated with each pool.
    mapping(address pool => IERC20[] poolTokens) internal _poolTokens;

    // The token configuration of each Pool's tokens.
    mapping(address pool => mapping(IERC20 token => TokenInfo tokenInfo)) internal _poolTokenInfo;

    // Structure containing the current raw and "last live" scaled balances. Last live balances are used for
    // yield fee computation, and since these have rates applied, they are stored as scaled 18-decimal FP values.
    // Each value takes up half the storage slot (i.e., 128 bits).
    mapping(address pool => mapping(uint256 tokenIndex => bytes32 packedTokenBalance)) internal _poolTokenBalances;

    // Aggregate protocol swap/yield fees accumulated in the Vault for harvest.
    // Reusing PackedTokenBalance for the bytes32 values to save bytecode (despite differing semantics).
    // It's arbitrary which is which: we define raw = swap; derived = yield.
    mapping(address pool => mapping(IERC20 token => bytes32 packedFeeAmounts)) internal _aggregateFeeAmounts;

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
    mapping(IERC20 token => uint256 vaultBalance) internal _reservesOf;

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
    mapping(IERC4626 wrappedToken => bytes32 packedTokenBalance) internal _bufferTokenBalances;

    // The LP balances for buffers. LP balances are not tokenized (i.e., represented by ERC20 tokens like BPT), but
    // rather accounted for within the Vault.

    // Track the internal "BPT" shares of each buffer depositor.
    mapping(IERC4626 wrappedToken => mapping(address user => uint256 userShares)) internal _bufferLpShares;

    // Total LP shares.
    mapping(IERC4626 wrappedToken => uint256 totalShares) internal _bufferTotalShares;

    // Prevents a malicious ERC4626 from changing the asset after the buffer was initialized.
    mapping(IERC4626 wrappedToken => address underlyingToken) internal _bufferAssets;

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
