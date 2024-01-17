// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/VaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";

import { PoolConfigLib } from "./lib/PoolConfigLib.sol";
import { VaultCommon } from "./VaultCommon.sol";

/**
 * @dev Bytecode extension for Vault.
 * Has access to the same storage layout as the main vault.
 *
 * The functions in this contract are not meant to be called directly ever. They should just be called by the Vault
 * via delegate calls instead, and any state modification produced by this contract's code will actually target
 * the main Vault's state.
 *
 * The storage of this contract is in practice unused.
 */
contract VaultExtension is IVaultExtension, VaultCommon {
    using EnumerableMap for EnumerableMap.IERC20ToUint256Map;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeCast for *;
    using PoolConfigLib for PoolConfig;

    IVault private immutable _vault;

    modifier onlyVault() {
        // If this is a delegate call from the vault, the address of the contract should be the Vault's,
        // not the extension.
        if (address(this) != address(_vault)) {
            revert NotVaultDelegateCall();
        }
        _;
    }

    constructor(IVault vault) Authentication(bytes32(uint256(uint160(address(vault))))) {
        _vault = vault;
    }

    /*******************************************************************************
                            Pool Registration and Initialization
    *******************************************************************************/

    /// @inheritdoc IVaultExtension
    function registerPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 pauseWindowEndTime,
        address pauseManager,
        PoolCallbacks calldata poolCallbacks,
        LiquidityManagement calldata liquidityManagement
    ) external nonReentrant whenVaultNotPaused onlyVault {
        _registerPool(pool, tokenConfig, pauseWindowEndTime, pauseManager, poolCallbacks, liquidityManagement);
    }

    /// @inheritdoc IVaultExtension
    function isPoolRegistered(address pool) external view onlyVault returns (bool) {
        return _isPoolRegistered(pool);
    }

    // Hello "stack too deep" my old friend
    struct RegistrationLocals {
        uint8[] tokenDecimalDiffs;
        IERC20[] tempRegisteredTokens;
        uint256 numTempTokens;
    }

    /**
     * @dev The function will register the pool, setting its tokens with an initial balance of zero.
     * The function also checks for valid token addresses and ensures that the pool and tokens aren't
     * already registered.
     *
     * Emits a `PoolRegistered` event upon successful registration.
     */
    function _registerPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 pauseWindowEndTime,
        address pauseManager,
        PoolCallbacks memory callbackConfig,
        LiquidityManagement memory liquidityManagement
    ) internal {
        // Ensure the pool isn't already registered
        if (_isPoolRegistered(pool)) {
            revert PoolAlreadyRegistered(pool);
        }

        uint256 numTokens = tokenConfig.length;

        if (numTokens < _MIN_TOKENS) {
            revert MinTokens();
        }
        if (numTokens > _MAX_TOKENS) {
            revert MaxTokens();
        }

        // Retrieve or create the pool's token balances mapping.
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];
        RegistrationLocals memory vars = _initRegistrationLocals(numTokens);
        uint256 i;

        for (i = 0; i < numTokens; ++i) {
            TokenConfig memory tokenData = tokenConfig[i];
            IERC20 token = tokenData.token;

            // Ensure that the token address is valid
            if (token == IERC20(address(0))) {
                revert InvalidToken();
            }

            // Register the token with an initial balance of zero.
            // Ensure the token isn't already registered for the pool.
            // Note: EnumerableMaps require an explicit initial value when creating a key-value pair.
            if (poolTokenBalances.set(token, 0) == false) {
                revert TokenAlreadyRegistered(address(token));
            }

            bool hasRateProvider = tokenData.rateProvider != IRateProvider(address(0));
            _poolTokenConfig[pool][token] = tokenData;

            if (tokenData.tokenType == TokenType.STANDARD) {
                if (hasRateProvider) {
                    revert InvalidTokenConfiguration();
                }
            } else if (tokenData.tokenType == TokenType.WITH_RATE) {
                if (hasRateProvider == false) {
                    revert InvalidTokenConfiguration();
                }
            } else if (tokenData.tokenType == TokenType.ERC4626) {
                // Ensure there is a token for this buffer.
                if (!_wrappedTokenBuffers.contains(address(token))) {
                    revert WrappedTokenBufferNotRegistered();
                }
                // ERC4626 tokens cannot have external rate providers, or be fee exempt.
                if (hasRateProvider || tokenData.yieldFeeExempt) {
                    revert InvalidTokenConfiguration();
                }

                // Replace the token actually registered with the base token, for the event.
                // Also temporarily register the token in order to detect duplicates. Since ERC4626
                // tokens appear to the outside as their base (e.g., waDAI would appear as DAI),
                // a DAI/waDAI pool would look like DAI/DAI, which we disallow with this check).
                IERC20 baseToken = _wrappedTokenBufferBaseTokens[token];
                if (poolTokenBalances.set(baseToken, 0)) {
                    // Store it to remove later, so that we don't actually include the base tokens
                    // in the pool.
                    vars.tempRegisteredTokens[vars.numTempTokens] = baseToken;
                    vars.numTempTokens++;
                } else {
                    // Depending on the token order (i.e., if the wrapped token comes first), it's possible
                    // for an ambiguous token to revert above with TokenAlreadyRegistered.
                    revert AmbiguousPoolToken(baseToken);
                }
            } else {
                revert InvalidTokenType();
            }

            vars.tokenDecimalDiffs[i] = uint8(18) - IERC20Metadata(address(token)).decimals();
        }

        // Remove any temporarily registered tokens.
        for (i = 0; i < vars.numTempTokens; i++) {
            poolTokenBalances.remove(vars.tempRegisteredTokens[i]);
        }

        // Store the pause manager. A zero address means default to the authorizer.
        _poolPauseManagers[pool] = pauseManager;

        // Store config and mark the pool as registered
        PoolConfig memory config = PoolConfigLib.toPoolConfig(_poolConfig[pool]);

        config.isPoolRegistered = true;
        config.callbacks = callbackConfig;
        config.liquidityManagement = liquidityManagement;
        config.tokenDecimalDiffs = PoolConfigLib.toTokenDecimalDiffs(vars.tokenDecimalDiffs);
        config.pauseWindowEndTime = pauseWindowEndTime.toUint32();
        _poolConfig[pool] = config.fromPoolConfig();

        // Emit an event to log the pool registration (pass msg.sender as the factory argument)
        emit PoolRegistered(
            pool,
            msg.sender,
            tokenConfig,
            pauseWindowEndTime,
            pauseManager,
            callbackConfig,
            liquidityManagement
        );
    }

    function _initRegistrationLocals(uint256 numTokens) private pure returns (RegistrationLocals memory vars) {
        vars.tokenDecimalDiffs = new uint8[](numTokens);
        vars.tempRegisteredTokens = new IERC20[](numTokens);
    }

    function _canPerform(bytes32 actionId, address user) internal view virtual override returns (bool) {
        return _authorizer.canPerform(actionId, user, address(this));
    }
}
