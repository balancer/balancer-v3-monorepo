// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Proxy } from "@openzeppelin/contracts/proxy/Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

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
    using SafeCast for *;
    using PoolConfigLib for PoolConfig;
    using InputHelpers for uint256;
    using ScalingHelpers for *;
    using VaultExtensionsLib for IVault;

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
    function getLocker(uint256 index) external view onlyVault returns (address) {
        if (index >= _lockers.length) {
            revert LockerOutOfBounds(index);
        }
        return _lockers[index];
    }

    /// @inheritdoc IVaultExtension
    function getLockersCount() external view onlyVault returns (uint256) {
        return _lockers.length;
    }

    /// @inheritdoc IVaultExtension
    function getNonzeroDeltaCount() external view onlyVault returns (uint256) {
        return _nonzeroDeltaCount;
    }

    /// @inheritdoc IVaultExtension
    function getTokenDelta(address user, IERC20 token) external view onlyVault returns (int256) {
        return _tokenDeltas[user][token];
    }

    /// @inheritdoc IVaultExtension
    function getTokenReserve(IERC20 token) external view onlyVault returns (uint256) {
        return _tokenReserves[token];
    }

    /*******************************************************************************
                            Pool Registration and Initialization
    *******************************************************************************/

    struct PoolRegistrationParams {
        TokenConfig[] tokenConfig;
        bool isBufferPool;
        uint256 pauseWindowEndTime;
        address pauseManager;
        PoolHooks poolHooks;
        LiquidityManagement liquidityManagement;
    }

    /// @inheritdoc IVaultExtension
    function registerPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 pauseWindowEndTime,
        address pauseManager,
        PoolHooks calldata poolHooks,
        LiquidityManagement calldata liquidityManagement
    ) external nonReentrant whenVaultNotPaused onlyVault {
        _registerPool(
            pool,
            PoolRegistrationParams({
                tokenConfig: tokenConfig,
                isBufferPool: false,
                pauseWindowEndTime: pauseWindowEndTime,
                pauseManager: pauseManager,
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
        IERC20[] memory tempRegisteredTokens = new IERC20[](numTokens);
        uint256 numTempTokens;

        for (uint256 i = 0; i < numTokens; ++i) {
            TokenConfig memory tokenData = params.tokenConfig[i];
            IERC20 token = tokenData.token;

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
                // Require a buffer to exist for this token
                if (_wrappedTokenBuffers[IERC4626(address(token))] == address(0)) {
                    revert WrappedTokenBufferNotRegistered();
                }

                // By definition, ERC4626 tokens are yield-bearing and subject to fees.
                if (tokenData.yieldFeeExempt) {
                    revert InvalidTokenConfiguration();
                }

                if (params.isBufferPool == false) {
                    // Temporarily register the base token in order to detect duplicates. Since ERC4626 tokens in
                    // regular (non-buffer) pool appear to the outside as their base (e.g., waDAI would appear as DAI),
                    // a DAI/waDAI pool - or cDAI/waDAI - would look like DAI/DAI, which we disallow with this check).
                    IERC20 baseToken = IERC20(IERC4626(address(token)).asset());
                    if (poolTokenBalances.set(baseToken, 0)) {
                        // Store it to remove later, so that we don't actually include the base tokens
                        // in the pool.
                        tempRegisteredTokens[numTempTokens++] = baseToken;
                    } else {
                        // We could introduce a new error here, but depending on the token order (i.e., if the wrapped
                        // token came first), it's possible to revert above with TokenAlreadyRegistered.
                        // For consistency, just use the same error in both places.
                        revert TokenAlreadyRegistered(baseToken);
                    }
                }
            } else {
                revert InvalidTokenType();
            }

            tokenDecimalDiffs[i] = uint8(18) - IERC20Metadata(address(token)).decimals();
        }

        // Delete any temporarily registered tokens.
        for (uint256 i = 0; i < numTempTokens; i++) {
            poolTokenBalances.remove(tempRegisteredTokens[i]);
        }

        // Store the pause manager. A zero address means default to the authorizer.
        _poolPauseManagers[pool] = params.pauseManager;

        // Store config and mark the pool as registered
        PoolConfig memory config = PoolConfigLib.toPoolConfig(_poolConfig[pool]);

        config.isPoolRegistered = true;
        config.hooks = params.poolHooks;
        config.liquidityManagement = params.liquidityManagement;
        config.tokenDecimalDiffs = PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs);
        config.pauseWindowEndTime = params.pauseWindowEndTime.toUint32();
        config.isBufferPool = params.isBufferPool;
        _poolConfig[pool] = config.fromPoolConfig();

        // Emit an event to log the pool registration (pass msg.sender as the factory argument)
        emit PoolRegistered(
            pool,
            msg.sender,
            params.tokenConfig,
            params.pauseWindowEndTime,
            params.pauseManager,
            params.poolHooks,
            params.liquidityManagement
        );
    }

    /// @inheritdoc IVaultExtension
    function initialize(
        address pool,
        address to,
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external withLocker withRegisteredPool(pool) whenPoolNotPaused(pool) onlyVault returns (uint256 bptAmountOut) {
        PoolData memory poolData = _computePoolDataUpdatingBalancesAndFees(pool, Rounding.ROUND_DOWN);

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
            _takeDebt(actualToken, exactAmountsIn[i], msg.sender);

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
        returns (
            IERC20[] memory tokens,
            TokenType[] memory tokenTypes,
            uint256[] memory balancesRaw,
            uint256[] memory decimalScalingFactors,
            IRateProvider[] memory rateProviders
        )
    {
        // Do not use _computePoolData, which makes external calls and could fail.
        TokenConfig[] memory tokenConfig;
        (tokenConfig, balancesRaw, decimalScalingFactors, ) = _getPoolTokenInfo(pool);

        uint256 numTokens = tokenConfig.length;
        tokens = new IERC20[](numTokens);
        tokenTypes = new TokenType[](numTokens);
        rateProviders = new IRateProvider[](numTokens);

        // TODO consider sending TokenConfig externally; maybe parallel arrays are friendlier off-chain.
        for (uint256 i = 0; i < numTokens; i++) {
            tokens[i] = tokenConfig[i].token;
            tokenTypes[i] = tokenConfig[i].tokenType;
            rateProviders[i] = tokenConfig[i].rateProvider;
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

        return (paused, pauseWindowEndTime, pauseWindowEndTime + _vaultBufferPeriodDuration, _poolPauseManagers[pool]);
    }

    /*******************************************************************************
                                        Fees
    *******************************************************************************/

    /// @inheritdoc IVaultExtension
    function getProtocolSwapFeePercentage() external view onlyVault returns (uint256) {
        return _protocolSwapFeePercentage;
    }

    /// @inheritdoc IVaultExtension
    function getProtocolYieldFeePercentage() external view onlyVault returns (uint256) {
        return _protocolYieldFeePercentage;
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
        withLocker
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
            _supplyCredit(tokens[i], amountsOutRaw[i], msg.sender);

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

        // Trusted routers use Vault's allowances, which are infinite anyways for pool tokens.
        if (!_isTrustedRouter(msg.sender)) {
            _spendAllowance(address(pool), from, msg.sender, exactBptAmountIn);
        }

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

        if (_isQueryDisabled) {
            revert QueriesDisabled();
        }

        // Add the current locker to the list so `withLocker` does not revert
        _lockers.push(msg.sender);
        _;
    }

    /// @inheritdoc IVaultExtension
    function quote(bytes calldata data) external payable query onlyVault returns (bytes memory result) {
        // Forward the incoming call to the original sender of this transaction.
        return (msg.sender).functionCallWithValue(data, msg.value);
    }

    /// @inheritdoc IVaultExtension
    function isQueryDisabled() external view onlyVault returns (bool) {
        return _isQueryDisabled;
    }

    /*******************************************************************************
-                                   ERC4626 Buffers
     *******************************************************************************/

    /// @inheritdoc IVaultExtension
    function registerBuffer(
        IERC4626 wrappedToken,
        address pool,
        address pauseManager,
        uint256 pauseWindowEndTime
    ) external nonReentrant whenVaultNotPaused onlyVault {
        // Ensure buffer does not already exist.
        if (_wrappedTokenBuffers[wrappedToken] != address(0)) {
            revert WrappedTokenBufferAlreadyRegistered();
        }

        // Ensure the buffer pool is from a registered factory
        bool factoryAllowed = false;

        for (uint256 i = 0; i < _bufferPoolFactories.length(); i++) {
            if (IBasePoolFactory(_bufferPoolFactories.unchecked_at(i)).isPoolFromFactory(pool)) {
                factoryAllowed = true;
                break;
            }
        }

        if (factoryAllowed == false) {
            revert UnregisteredBufferPoolFactory();
        }

        _wrappedTokenBuffers[wrappedToken] = pool;

        IERC20 baseToken = IERC20(wrappedToken.asset());

        emit WrappedTokenBufferCreated(address(wrappedToken), address(baseToken));

        // Token order is wrapped first, then base.
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[0].token = IERC20(wrappedToken);
        tokenConfig[0].tokenType = TokenType.ERC4626;
        // We are assuming the baseToken is STANDARD (the default type, with enum value 0).
        tokenConfig[1].token = baseToken;

        _registerPool(
            pool,
            PoolRegistrationParams({
                tokenConfig: tokenConfig,
                isBufferPool: true,
                pauseWindowEndTime: pauseWindowEndTime,
                pauseManager: pauseManager,
                poolHooks: PoolHooks({
                    shouldCallBeforeInitialize: true, // ensure proportional
                    shouldCallAfterInitialize: false,
                    shouldCallBeforeAddLiquidity: true, // ensure custom
                    shouldCallAfterAddLiquidity: false,
                    shouldCallBeforeRemoveLiquidity: true, // ensure proportional
                    shouldCallAfterRemoveLiquidity: false,
                    shouldCallBeforeSwap: true, // rebalancing
                    shouldCallAfterSwap: false
                }),
                liquidityManagement: LiquidityManagement({
                    supportsAddLiquidityCustom: true,
                    supportsRemoveLiquidityCustom: false
                })
            })
        );
    }

    /*******************************************************************************
                                     Default lockers
    *******************************************************************************/

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
