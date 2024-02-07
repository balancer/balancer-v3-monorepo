// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";

import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";

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
    // TODO Optimize storage; could pack fees into one slot (potentially a single vaultConfig slot).
    uint256 internal constant _MAX_PROTOCOL_YIELD_FEE_PERCENTAGE = 20e16; // 20%

    // Maximum pool swap fee percentage.
    uint256 internal constant _MAX_SWAP_FEE_PERCENTAGE = 10e16; // 10%

    // Code extension for Vault.
    IVaultExtension internal immutable _vaultExtension;

    // Registry of pool configs.
    mapping(address => PoolConfigBits) internal _poolConfig;

    // Store pool pause managers.
    mapping(address => address) internal _poolPauseManagers;

    // Pool -> (token -> balance): Pool's ERC20 tokens balances stored at the Vault.
    mapping(address => EnumerableMap.IERC20ToUint256Map) internal _poolTokenBalances;

    // Pool -> (token -> balance): Pool's last live balances, used for yield fee computation
    // Note that since these have rates applied, they are stored as "scaled" 18-decimal FP values.
    // TODO - storage will be optimized later (e.g., both balances can be stored in 128 bits each)
    mapping(address => EnumerableMap.IERC20ToUint256Map) internal _lastLivePoolTokenBalances;

    // Pool -> (token -> TokenConfig): The token configuration of each Pool's tokens.
    mapping(address => mapping(IERC20 => TokenConfig)) internal _poolTokenConfig;

    // Pool -> (token -> address): Pool's Rate providers.
    mapping(address => mapping(IERC20 => IRateProvider)) internal _poolRateProviders;

    /// @notice List of handlers. It is non-empty only during `invoke` calls.
    address[] internal _handlers;

    /**
     * @notice The total number of nonzero deltas over all active + completed lockers.
     * @dev It is non-zero only during `invoke` calls.
     */
    uint256 internal _nonzeroDeltaCount;

    /**
     * @notice Represents the token due/owed to each handler.
     * @dev Must all net to zero when the last handler is released.
     */
    mapping(address => mapping(IERC20 => int256)) internal _tokenDeltas;

    /**
     * @notice Represents the total reserve of each ERC20 token.
     * @dev It should be always equal to `token.balanceOf(vault)`, except during `invoke`.
     */
    mapping(IERC20 => uint256) internal _tokenReserves;

    // We allow 0% swap fee.
    // The protocol swap fee is charged whenever a swap occurs, as a percentage of the fee charged by the Pool.
    // TODO consider using uint64 and packing with other things (when we have other things).
    uint256 internal _protocolSwapFeePercentage;

    // Protocol yield fee - charged on all pool operations.
    uint256 internal _protocolYieldFeePercentage;

    // Token -> fee: Protocol fees (from both swap and yield) accumulated in the Vault for harvest.
    mapping(IERC20 => uint256) internal _protocolFees;

    // Upgradeable contract in charge of setting permissions.
    IAuthorizer internal _authorizer;

    /// @notice If set to true, disables query functionality of the Vault. Can be modified only by governance.
    bool internal _isQueryDisabled;

    uint256 public constant MAX_PAUSE_WINDOW_DURATION = 356 days * 4;
    uint256 public constant MAX_BUFFER_PERIOD_DURATION = 90 days;

    // The Pause Window and Buffer Period are timestamp-based: they should not be relied upon for sub-minute accuracy.
    // solhint-disable not-rely-on-time

    uint256 internal immutable _vaultPauseWindowEndTime;
    uint256 internal immutable _vaultBufferPeriodEndTime;
    // Stored as a convenience, to avoid calculating it on every operation.
    uint256 internal immutable _vaultBufferPeriodDuration;

    bool internal _vaultPaused;
}
