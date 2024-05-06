// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Proxy } from "@openzeppelin/contracts/proxy/Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";
import { StorageSlot } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlot.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { VaultStateBits, VaultStateLib } from "./lib/VaultStateLib.sol";
import { PoolConfigLib } from "./lib/PoolConfigLib.sol";
import { VaultExtensionsLib } from "./lib/VaultExtensionsLib.sol";
import { VaultCommon } from "./VaultCommon.sol";
import { PackedTokenBalance } from "./lib/PackedTokenBalance.sol";

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
contract VaultExtension is IVaultExtension, VaultCommon, Proxy {
    using Address for *;
    using ArrayHelpers for uint256[];
    using EnumerableMap for EnumerableMap.IERC20ToBytes32Map;
    using EnumerableSet for EnumerableSet.AddressSet;
    using PackedTokenBalance for bytes32;
    using PoolConfigLib for PoolConfig;
    using InputHelpers for uint256;
    using ScalingHelpers for *;
    using VaultExtensionsLib for IVault;
    using VaultStateLib for VaultStateBits;
    using TransientStorageHelpers for *;
    using StorageSlot for *;

    IVault private immutable _vault;
    IVaultAdmin private immutable _vaultAdmin;

    /// @dev Functions with this modifier can only be delegate-called by the vault.
    modifier onlyVault() {
        _ensureVaultDelegateCall();
        _;
    }

    function _ensureVaultDelegateCall() internal view {
        _vault.ensureVaultDelegateCall();
    }

    constructor(IVault mainVault, IVaultAdmin vaultAdmin) {
        if (vaultAdmin.vault() != mainVault) {
            revert WrongVaultAdminDeployment();
        }

        _vaultPauseWindowEndTime = vaultAdmin.getPauseWindowEndTime();
        _vaultBufferPeriodDuration = vaultAdmin.getBufferPeriodDuration();
        _vaultBufferPeriodEndTime = vaultAdmin.getBufferPeriodEndTime();

        _vault = mainVault;
        _vaultAdmin = vaultAdmin;
    }

    function vault() external view returns (IVault) {
        return _vault;
    }

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /// @inheritdoc IVaultExtension
    function isUnlocked() external view onlyVault returns (bool) {
        return _isUnlocked().tload();
    }

    /// @inheritdoc IVaultExtension
    function getNonzeroDeltaCount() external view onlyVault returns (uint256) {
        return _nonzeroDeltaCount().tload();
    }

    /// @inheritdoc IVaultExtension
    function getTokenDelta(IERC20 token) external view onlyVault returns (int256) {
        return _tokenDeltas().tGet(token);
    }

    /// @inheritdoc IVaultExtension
    function getReservesOf(IERC20 token) external view onlyVault returns (uint256) {
        return _reservesOf[token];
    }

    /*******************************************************************************
                            Pool Registration and Initialization
    *******************************************************************************/

    struct PoolRegistrationParams {
        TokenConfig[] tokenConfig;
        uint256 swapFeePercentage;
        uint256 pauseWindowEndTime;
        PoolRoleAccounts roleAccounts;
        PoolHooks poolHooks;
        LiquidityManagement liquidityManagement;
    }

    /// @inheritdoc IVaultExtension
    function registerPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 swapFeePercentage,
        uint256 pauseWindowEndTime,
        PoolRoleAccounts calldata roleAccounts,
        PoolHooks calldata poolHooks,
        LiquidityManagement calldata liquidityManagement
    ) external nonReentrant whenVaultNotPaused onlyVault {
        _registerPool(
            pool,
            PoolRegistrationParams({
                tokenConfig: tokenConfig,
                swapFeePercentage: swapFeePercentage,
                pauseWindowEndTime: pauseWindowEndTime,
                roleAccounts: roleAccounts,
                poolHooks: poolHooks,
                liquidityManagement: liquidityManagement
            })
        );
    }

    /// @inheritdoc IVaultExtension
    function isPoolRegistered(address pool) external view onlyVault returns (bool) {
        return _isPoolRegistered(pool);
    }

    /**
     * @dev The function will register the pool, setting its tokens with an initial balance of zero.
     * The function also checks for valid token addresses and ensures that the pool and tokens aren't
     * already registered.
     *
     * Emits a `PoolRegistered` event upon successful registration.
     */
    function _registerPool(address pool, PoolRegistrationParams memory params) internal {
        // Ensure the pool isn't already registered
        if (_isPoolRegistered(pool)) {
            revert PoolAlreadyRegistered(pool);
        }

        uint256 numTokens = params.tokenConfig.length;
        if (numTokens < _MIN_TOKENS) {
            revert MinTokens();
        }
        if (numTokens > _MAX_TOKENS) {
            revert MaxTokens();
        }

        // Retrieve or create the pool's token balances mapping.
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances = _poolTokenBalances[pool];

        uint8[] memory tokenDecimalDiffs = new uint8[](numTokens);
        IERC20 previousToken;

        for (uint256 i = 0; i < numTokens; ++i) {
            TokenConfig memory tokenData = params.tokenConfig[i];
            IERC20 token = tokenData.token;

            // Enforce token sorting. (`previousToken` will be the zero address on the first iteration.)
            if (token < previousToken) {
                revert InputHelpers.TokensNotSorted();
            }
            previousToken = token;

            // Ensure that the token address is valid
            if (address(token) == address(0) || address(token) == pool) {
                revert InvalidToken();
            }

            // Register the token with an initial balance of zero.
            // Ensure the token isn't already registered for the pool.
            // Note: EnumerableMaps require an explicit initial value when creating a key-value pair.
            if (poolTokenBalances.set(token, bytes32(0)) == false) {
                revert TokenAlreadyRegistered(token);
            }

            // Register the token dev fee with an initial balance of zero.
            _poolCreatorFees[pool][address(token)] = 0;

            bool hasRateProvider = tokenData.rateProvider != IRateProvider(address(0));
            _poolTokenConfig[pool][token] = tokenData;

            if (tokenData.tokenType == TokenType.STANDARD) {
                if (hasRateProvider || tokenData.paysYieldFees) {
                    revert InvalidTokenConfiguration();
                }
            } else if (tokenData.tokenType == TokenType.WITH_RATE) {
                if (hasRateProvider == false) {
                    revert InvalidTokenConfiguration();
                }
            } else {
                revert InvalidTokenType();
            }

            tokenDecimalDiffs[i] = uint8(18) - IERC20Metadata(address(token)).decimals();
        }

        // Store the role account addresses (for getters).
        _poolRoleAccounts[pool] = params.roleAccounts;

        // Make pool role assignments. A zero address means default to the authorizer.
        _assignPoolRoles(pool, params.roleAccounts);

        // Store config and mark the pool as registered
        PoolConfig memory config = PoolConfigLib.toPoolConfig(_poolConfig[pool]);

        config.isPoolRegistered = true;
        config.hooks = params.poolHooks;
        config.liquidityManagement = params.liquidityManagement;
        config.tokenDecimalDiffs = PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs);
        config.pauseWindowEndTime = params.pauseWindowEndTime;
        _poolConfig[pool] = config.fromPoolConfig();

        _setStaticSwapFeePercentage(pool, params.swapFeePercentage);

        // Emit an event to log the pool registration (pass msg.sender as the factory argument)
        emit PoolRegistered(
            pool,
            msg.sender,
            params.tokenConfig,
            params.pauseWindowEndTime,
            params.roleAccounts,
            params.poolHooks,
            params.liquidityManagement
        );
    }

    function _assignPoolRoles(address pool, PoolRoleAccounts memory roleAccounts) private {
        mapping(bytes32 => PoolFunctionPermission) storage roleAssignments = _poolFunctionPermissions[pool];
        IAuthentication vaultAdmin = IAuthentication(address(_vaultAdmin));

        if (roleAccounts.pauseManager != address(0)) {
            roleAssignments[vaultAdmin.getActionId(IVaultAdmin.pausePool.selector)] = PoolFunctionPermission({
                account: roleAccounts.pauseManager,
                onlyOwner: false
            });
            roleAssignments[vaultAdmin.getActionId(IVaultAdmin.unpausePool.selector)] = PoolFunctionPermission({
                account: roleAccounts.pauseManager,
                onlyOwner: false
            });
        }

        if (roleAccounts.swapFeeManager != address(0)) {
            bytes32 swapFeeAction = vaultAdmin.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector);

            roleAssignments[swapFeeAction] = PoolFunctionPermission({
                account: roleAccounts.swapFeeManager,
                onlyOwner: true
            });
        }

        if (roleAccounts.poolCreator != address(0)) {
            bytes32 creatorFeeAction = vaultAdmin.getActionId(IVaultAdmin.setPoolCreatorFeePercentage.selector);

            roleAssignments[creatorFeeAction] = PoolFunctionPermission({
                account: roleAccounts.poolCreator,
                onlyOwner: true
            });
        }
    }

    /// @inheritdoc IVaultExtension
    function initialize(
        address pool,
        address to,
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external onlyWhenUnlocked withRegisteredPool(pool) onlyVault returns (uint256 bptAmountOut) {
        VaultState memory vaultState = _ensureUnpausedAndGetVaultState(pool);

        PoolData memory poolData = _computePoolDataUpdatingBalancesAndFees(
            pool,
            Rounding.ROUND_DOWN,
            vaultState.protocolYieldFeePercentage
        );

        if (poolData.poolConfig.isPoolInitialized) {
            revert PoolAlreadyInitialized(pool);
        }
        uint256 numTokens = poolData.tokenConfig.length;

        InputHelpers.ensureInputLengthMatch(numTokens, exactAmountsIn.length);

        // Amounts are entering pool math, so round down. A lower invariant after the join means less bptOut,
        // favoring the pool.
        uint256[] memory exactAmountsInScaled18 = exactAmountsIn.copyToScaled18ApplyRateRoundDownArray(
            poolData.decimalScalingFactors,
            poolData.tokenRates
        );

        if (poolData.poolConfig.hooks.shouldCallBeforeInitialize) {
            if (IPoolHooks(pool).onBeforeInitialize(exactAmountsInScaled18, userData) == false) {
                revert BeforeInitializeHookFailed();
            }

            // The before hook is reentrant, and could have changed token rates.
            _updateTokenRatesInPoolData(poolData);

            // Also update exactAmountsInScaled18, in case the underlying rates changed.
            exactAmountsInScaled18 = exactAmountsIn.copyToScaled18ApplyRateRoundDownArray(
                poolData.decimalScalingFactors,
                poolData.tokenRates
            );
        }

        bptAmountOut = _initialize(pool, to, poolData, tokens, exactAmountsIn, exactAmountsInScaled18, minBptAmountOut);

        if (poolData.poolConfig.hooks.shouldCallAfterInitialize) {
            if (IPoolHooks(pool).onAfterInitialize(exactAmountsInScaled18, bptAmountOut, userData) == false) {
                revert AfterInitializeHookFailed();
            }
        }
    }

    function _initialize(
        address pool,
        address to,
        PoolData memory poolData,
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        uint256[] memory exactAmountsInScaled18,
        uint256 minBptAmountOut
    ) internal nonReentrant returns (uint256 bptAmountOut) {
        EnumerableMap.IERC20ToBytes32Map storage poolBalances = _poolTokenBalances[pool];

        for (uint256 i = 0; i < poolData.tokenConfig.length; ++i) {
            IERC20 actualToken = poolData.tokenConfig[i].token;

            // Tokens passed into `initialize` are the "expected" tokens.
            if (actualToken != tokens[i]) {
                revert TokensMismatch(pool, address(tokens[i]), address(actualToken));
            }

            // Debit of token[i] for amountIn
            _takeDebt(actualToken, exactAmountsIn[i]);

            // Store the new Pool balances (and initial last live balances).
            poolBalances.unchecked_setAt(
                i,
                PackedTokenBalance.toPackedBalance(exactAmountsIn[i], exactAmountsInScaled18[i])
            );
        }

        emit PoolBalanceChanged(pool, to, tokens, exactAmountsIn.unsafeCastToInt256(true));

        // Store config and mark the pool as initialized
        poolData.poolConfig.isPoolInitialized = true;
        _poolConfig[pool] = poolData.poolConfig.fromPoolConfig();

        // Pass scaled balances to the pool
        bptAmountOut = IBasePool(pool).computeInvariant(exactAmountsInScaled18);

        _ensureMinimumTotalSupply(bptAmountOut);

        // At this point we know that bptAmountOut >= _MINIMUM_TOTAL_SUPPLY, so this will not revert.
        bptAmountOut -= _MINIMUM_TOTAL_SUPPLY;
        // When adding liquidity, we must mint tokens concurrently with updating pool balances,
        // as the pool's math relies on totalSupply.
        // Minting will be reverted if it results in a total supply less than the _MINIMUM_TOTAL_SUPPLY.
        _mintMinimumSupplyReserve(address(pool));
        _mint(address(pool), to, bptAmountOut);

        // At this point we have the calculated BPT amount.
        if (bptAmountOut < minBptAmountOut) {
            revert BptAmountOutBelowMin(bptAmountOut, minBptAmountOut);
        }

        // Emit an event to log the pool initialization
        emit PoolInitialized(pool);
    }

    /*******************************************************************************
                                    Pool Information
    *******************************************************************************/

    /// @inheritdoc IVaultExtension
    function isPoolInitialized(address pool) external view withRegisteredPool(pool) onlyVault returns (bool) {
        return _isPoolInitialized(pool);
    }

    /// @inheritdoc IVaultExtension
    function getPoolConfig(address pool) external view withRegisteredPool(pool) onlyVault returns (PoolConfig memory) {
        return _poolConfig[pool].toPoolConfig();
    }

    /// @inheritdoc IVaultExtension
    function getPoolTokens(address pool) external view withRegisteredPool(pool) onlyVault returns (IERC20[] memory) {
        return _getPoolTokens(pool);
    }

    /// @inheritdoc IVaultExtension
    function getPoolTokenInfo(
        address pool
    )
        external
        view
        withRegisteredPool(pool)
        returns (TokenConfig[] memory tokenConfig, uint256[] memory balancesRaw, uint256[] memory decimalScalingFactors)
    {
        (tokenConfig, balancesRaw, decimalScalingFactors, ) = _getPoolTokenInfo(pool);
    }

    /// @inheritdoc IVaultExtension
    function computeDynamicSwapFee(
        address pool,
        IBasePool.PoolSwapParams memory swapParams
    ) external view withRegisteredPool(pool) returns (bool success, uint256 dynamicSwapFee) {
        bool shouldCallDynamicSwapFee = _poolConfig[pool].shouldCallComputeDynamicSwapFee();

        if (shouldCallDynamicSwapFee) {
            (success, dynamicSwapFee) = IPoolHooks(pool).onComputeDynamicSwapFee(swapParams);
        }
    }

    /*******************************************************************************
                                    Pool Tokens
    *******************************************************************************/

    /// @inheritdoc IVaultExtension
    function totalSupply(address token) external view onlyVault returns (uint256) {
        return _totalSupply(token);
    }

    /// @inheritdoc IVaultExtension
    function balanceOf(address token, address account) external view onlyVault returns (uint256) {
        return _balanceOf(token, account);
    }

    /// @inheritdoc IVaultExtension
    function allowance(address token, address owner, address spender) external view onlyVault returns (uint256) {
        return _allowance(token, owner, spender);
    }

    /// @inheritdoc IVaultExtension
    function transfer(address owner, address to, uint256 amount) external onlyVault returns (bool) {
        _transfer(msg.sender, owner, to, amount);
        return true;
    }

    /// @inheritdoc IVaultExtension
    function approve(address owner, address spender, uint256 amount) external onlyVault returns (bool) {
        _approve(msg.sender, owner, spender, amount);
        return true;
    }

    /// @inheritdoc IVaultExtension
    function transferFrom(address spender, address from, address to, uint256 amount) external onlyVault returns (bool) {
        _spendAllowance(msg.sender, from, spender, amount);
        _transfer(msg.sender, from, to, amount);
        return true;
    }

    /*******************************************************************************
                                     Pool Pausing
    *******************************************************************************/

    /// @inheritdoc IVaultExtension
    function isPoolPaused(address pool) external view withRegisteredPool(pool) onlyVault returns (bool) {
        return _isPoolPaused(pool);
    }

    /// @inheritdoc IVaultExtension
    function getPoolPausedState(
        address pool
    ) external view withRegisteredPool(pool) onlyVault returns (bool, uint256, uint256, address) {
        (bool paused, uint256 pauseWindowEndTime) = _getPoolPausedState(pool);

        return (
            paused,
            pauseWindowEndTime,
            pauseWindowEndTime + _vaultBufferPeriodDuration,
            _poolRoleAccounts[pool].pauseManager
        );
    }

    /*******************************************************************************
                                        Fees
    *******************************************************************************/

    /// @inheritdoc IVaultExtension
    function getProtocolSwapFeePercentage() external view onlyVault returns (uint256) {
        return _vaultState.getProtocolSwapFeePercentage();
    }

    /// @inheritdoc IVaultExtension
    function getProtocolYieldFeePercentage() external view onlyVault returns (uint256) {
        return _vaultState.getProtocolYieldFeePercentage();
    }

    /// @inheritdoc IVaultExtension
    function getProtocolFees(address token) external view onlyVault returns (uint256) {
        return _protocolFees[IERC20(token)];
    }

    /// @inheritdoc IVaultExtension
    function getStaticSwapFeePercentage(
        address pool
    ) external view withRegisteredPool(pool) onlyVault returns (uint256) {
        return PoolConfigLib.toPoolConfig(_poolConfig[pool]).staticSwapFeePercentage;
    }

    /// @inheritdoc IVaultExtension
    function getStaticSwapFeeManager(address pool) external view withRegisteredPool(pool) onlyVault returns (address) {
        return _poolRoleAccounts[pool].swapFeeManager;
    }

    /// @inheritdoc IVaultExtension
    function getPoolCreatorFees(address pool, IERC20 token) external view returns (uint256) {
        return _poolCreatorFees[pool][address(token)];
    }

    /// @inheritdoc IVaultExtension
    function getPoolCreator(address pool) external view returns (address poolCreator) {
        return _poolRoleAccounts[pool].poolCreator;
    }

    /*******************************************************************************
                                    Recovery Mode
    *******************************************************************************/

    /// @inheritdoc IVaultExtension
    function isPoolInRecoveryMode(address pool) external view withRegisteredPool(pool) onlyVault returns (bool) {
        return _isPoolInRecoveryMode(pool);
    }

    /// @inheritdoc IVaultExtension
    function removeLiquidityRecovery(
        address pool,
        address from,
        uint256 exactBptAmountIn
    )
        external
        onlyWhenUnlocked
        nonReentrant
        withInitializedPool(pool)
        onlyInRecoveryMode(pool)
        returns (uint256[] memory amountsOutRaw)
    {
        // Retrieve the mapping of tokens and their balances for the specified pool.
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances = _poolTokenBalances[pool];
        uint256 numTokens = poolTokenBalances.length();

        // Initialize arrays to store tokens and balances based on the number of tokens in the pool.
        IERC20[] memory tokens = new IERC20[](numTokens);
        uint256[] memory balancesRaw = new uint256[](numTokens);
        bytes32 packedBalances;

        for (uint256 i = 0; i < numTokens; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length,
            // we can safely use `unchecked_at`. This ensures that `i` is a valid token index and minimizes
            // storage reads.
            (tokens[i], packedBalances) = poolTokenBalances.unchecked_at(i);
            balancesRaw[i] = packedBalances.getRawBalance();
        }

        amountsOutRaw = BasePoolMath.computeProportionalAmountsOut(balancesRaw, _totalSupply(pool), exactBptAmountIn);

        for (uint256 i = 0; i < numTokens; ++i) {
            // Credit token[i] for amountOut
            _supplyCredit(tokens[i], amountsOutRaw[i]);

            // Compute the new Pool balances. A Pool's token balance always decreases after an exit
            // (potentially by 0).
            balancesRaw[i] -= amountsOutRaw[i];
        }

        // Store the new pool balances - raw only, since we don't have rates in Recovery Mode.
        // In Recovery Mode, raw and last live balances will get out of sync. This is corrected when the pool is taken
        // out of Recovery Mode.
        EnumerableMap.IERC20ToBytes32Map storage poolBalances = _poolTokenBalances[pool];

        for (uint256 i = 0; i < numTokens; ++i) {
            packedBalances = poolBalances.unchecked_valueAt(i);
            poolBalances.unchecked_setAt(i, packedBalances.setRawBalance(balancesRaw[i]));
        }

        _spendAllowance(address(pool), from, msg.sender, exactBptAmountIn);

        // When removing liquidity, we must burn tokens concurrently with updating pool balances,
        // as the pool's math relies on totalSupply.
        // Burning will be reverted if it results in a total supply less than the _MINIMUM_TOTAL_SUPPLY.
        _burn(address(pool), from, exactBptAmountIn);

        emit PoolBalanceChanged(
            pool,
            from,
            tokens,
            // We can unsafely cast to int256 because balances are stored as uint128 (see PackedTokenBalance).
            amountsOutRaw.unsafeCastToInt256(false)
        );
    }

    /*******************************************************************************
                                        Queries
    *******************************************************************************/

    /// @dev Ensure that only static calls are made to the functions with this modifier.
    modifier query() {
        if (!EVMCallModeHelpers.isStaticCall()) {
            revert EVMCallModeHelpers.NotStaticCall();
        }

        bool _isQueryDisabled = _vaultState.isQueryDisabled();
        if (_isQueryDisabled) {
            revert QueriesDisabled();
        }

        // Unlock so that `onlyWhenUnlocked` does not revert
        _isUnlocked().tstore(true);
        _;
    }

    /// @inheritdoc IVaultExtension
    function quote(bytes calldata data) external payable query onlyVault returns (bytes memory result) {
        // Forward the incoming call to the original sender of this transaction.
        return (msg.sender).functionCallWithValue(data, msg.value);
    }

    /// @inheritdoc IVaultExtension
    function isQueryDisabled() external view onlyVault returns (bool) {
        return _vaultState.isQueryDisabled();
    }

    receive() external payable {
        revert CannotReceiveEth();
    }

    // solhint-disable no-complex-fallback

    /**
     * @inheritdoc Proxy
     * @dev Override proxy implementation of `fallback` to disallow incoming ETH transfers.
     * This function actually returns whatever the Vault Extension does when handling the request.
     */
    fallback() external payable override {
        if (msg.value > 0) {
            revert CannotReceiveEth();
        }

        _fallback();
    }

    /// @inheritdoc IVaultExtension
    function getVaultAdmin() external view returns (address) {
        return _implementation();
    }

    /**
     * @inheritdoc Proxy
     * @dev Returns Vault Extension, where fallback requests are forwarded.
     */
    function _implementation() internal view override returns (address) {
        return address(_vaultAdmin);
    }
}
