// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";
import { PoolConfigBits } from "./lib/PoolConfigLib.sol";

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

    // 1e18 corresponds to a 100% fee.
    uint256 internal constant _MAX_PROTOCOL_SWAP_FEE_PERCENTAGE = 50e16; // 50%

    // 1e18 corresponds to a 100% fee.
    uint256 internal constant _MAX_SWAP_FEE_PERCENTAGE = 10e16; // 10%

    // Code extension for Vault.
    IVaultExtension internal immutable _vaultExtension;

    // Registry of pool configs.
    mapping(address => PoolConfigBits) internal _poolConfig;

    // Store pool pause managers.
    mapping(address => address) internal _poolPauseManagers;

    // Pool -> (token -> balance): Pool's ERC20 tokens balances stored at the Vault.
    mapping(address => EnumerableMap.IERC20ToUint256Map) internal _poolTokenBalances;

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

    // Token -> fee: Protocol's swap fees accumulated in the Vault for harvest.
    mapping(IERC20 => uint256) internal _protocolSwapFees;

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

    // ERC4626 wrapped token buffers

    EnumerableSet.AddressSet internal _wrappedTokenBuffers;

    // For convenience, store the base token for each buffer in `_wrappedTokenBuffers`
    mapping(IERC20 => IERC20) internal _wrappedTokenBufferBaseTokens;

    mapping(IERC20 => EnumerableMap.IERC20ToUint256Map) internal _bufferDepositorShares;

    // Decimal difference used for wrapped token rate computation.
    EnumerableMap.IERC20ToUint256Map internal _bufferRateScalingFactors;

    // Record the total supply of each buffer (adjusted by deposits/withdrawals from buffers)
    EnumerableMap.IERC20ToUint256Map internal _bufferTotalSupply;

    // TODO: (buffer -> balances) - Encoded balances for each buffer (packed base + wrapped).
    // EnumerableMap.IERC20ToBytes32Map internal _wrappedTokenBufferBalances;
}
