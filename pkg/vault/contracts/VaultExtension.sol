// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Proxy } from "@openzeppelin/contracts/proxy/Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { RevertCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/RevertCodec.sol";
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
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { VaultStateBits, VaultStateLib } from "./lib/VaultStateLib.sol";
import { PoolConfigLib } from "./lib/PoolConfigLib.sol";
import { HooksConfigLib, HooksConfigBits } from "./lib/HooksConfigLib.sol";
import { VaultExtensionsLib } from "./lib/VaultExtensionsLib.sol";
import { VaultCommon } from "./VaultCommon.sol";
import { PackedTokenBalance } from "./lib/PackedTokenBalance.sol";
import { PoolDataLib } from "./lib/PoolDataLib.sol";

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
    using FixedPoint for uint256;
    using EnumerableMap for EnumerableMap.IERC20ToBytes32Map;
    using EnumerableSet for EnumerableSet.AddressSet;
    using PackedTokenBalance for bytes32;
    using PoolConfigLib for PoolConfigBits;
    using InputHelpers for uint256;
    using ScalingHelpers for *;
    using VaultExtensionsLib for IVault;
    using TransientStorageHelpers for *;
    using StorageSlot for *;
    using PoolDataLib for PoolData;

    IVault private immutable _vault;
    IVaultAdmin private immutable _vaultAdmin;

    /// @dev Functions with this modifier can only be delegate-called by the vault.
    modifier onlyVaultDelegateCall() {
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
    function isUnlocked() external view onlyVaultDelegateCall returns (bool) {
        return _isUnlocked().tload();
    }

    /// @inheritdoc IVaultExtension
    function getNonzeroDeltaCount() external view onlyVaultDelegateCall returns (uint256) {
        return _nonZeroDeltaCount().tload();
    }

    /// @inheritdoc IVaultExtension
    function getTokenDelta(IERC20 token) external view onlyVaultDelegateCall returns (int256) {
        return _tokenDeltas().tGet(token);
    }

    /// @inheritdoc IVaultExtension
    function getReservesOf(IERC20 token) external view onlyVaultDelegateCall returns (uint256) {
        return _reservesOf[token];
    }

    /*******************************************************************************
                            Pool Registration and Initialization
    *******************************************************************************/

    struct PoolRegistrationParams {
        TokenConfig[] tokenConfig;
        uint256 swapFeePercentage;
        uint32 pauseWindowEndTime;
        bool protocolFeeExempt;
        PoolRoleAccounts roleAccounts;
        address poolHooksContract;
        LiquidityManagement liquidityManagement;
    }

    /// @inheritdoc IVaultExtension
    function registerPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 swapFeePercentage,
        uint32 pauseWindowEndTime,
        bool protocolFeeExempt,
        PoolRoleAccounts calldata roleAccounts,
        address poolHooksContract,
        LiquidityManagement calldata liquidityManagement
    ) external onlyVaultDelegateCall nonReentrant whenVaultNotPaused {
        _registerPool(
            pool,
            PoolRegistrationParams({
                tokenConfig: tokenConfig,
                swapFeePercentage: swapFeePercentage,
                pauseWindowEndTime: pauseWindowEndTime,
                protocolFeeExempt: protocolFeeExempt,
                roleAccounts: roleAccounts,
                poolHooksContract: poolHooksContract,
                liquidityManagement: liquidityManagement
            })
        );
    }

    /// @inheritdoc IVaultExtension
    function isPoolRegistered(address pool) external view onlyVaultDelegateCall returns (bool) {
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

        HooksConfigBits hooksConfig = _hooksConfigBits[pool];

        if (params.poolHooksContract != address(0)) {
            // If a hook address was passed, make sure that hook trusts the pool factory
            if (
                IHooks(params.poolHooksContract).onRegister(
                    msg.sender,
                    pool,
                    params.tokenConfig,
                    params.liquidityManagement
                ) == false
            ) {
                revert HookRegistrationFailed(params.poolHooksContract, pool, msg.sender);
            }

            // Gets the default HooksConfig from the hook contract and saves in the vault state
            // Storing into hooksConfig first avoids stack-too-deep
            IHooks.HookFlags memory hookFlags = IHooks(params.poolHooksContract).getHookFlags();

            // When enableHookAdjustedAmounts == true, hooks are able to modify the result of a liquidity or swap
            // operation by implementing an after hook. For simplicity, the vault only supports modifying the
            // calculated part of the operation. As such, when a hook supports adjusted amounts, it can not support
            // unbalanced liquidity operations as this would introduce instances where the amount calculated is the
            // input amount (EXACT_OUT).
            if (hookFlags.enableHookAdjustedAmounts && params.liquidityManagement.disableUnbalancedLiquidity == false) {
                revert HookRegistrationFailed(params.poolHooksContract, pool, msg.sender);
            }

            hooksConfig = hooksConfig.setHookAdjustedAmounts(hookFlags.enableHookAdjustedAmounts);
            hooksConfig = hooksConfig.setShouldCallBeforeInitialize(hookFlags.shouldCallBeforeInitialize);
            hooksConfig = hooksConfig.setShouldCallAfterInitialize(hookFlags.shouldCallAfterInitialize);
            hooksConfig = hooksConfig.setShouldCallComputeDynamicSwapFee(hookFlags.shouldCallComputeDynamicSwapFee);
            hooksConfig = hooksConfig.setShouldCallBeforeSwap(hookFlags.shouldCallBeforeSwap);
            hooksConfig = hooksConfig.setShouldCallAfterSwap(hookFlags.shouldCallAfterSwap);
            hooksConfig = hooksConfig.setShouldCallBeforeAddLiquidity(hookFlags.shouldCallBeforeAddLiquidity);
            hooksConfig = hooksConfig.setShouldCallAfterAddLiquidity(hookFlags.shouldCallAfterAddLiquidity);
            hooksConfig = hooksConfig.setShouldCallBeforeRemoveLiquidity(hookFlags.shouldCallBeforeRemoveLiquidity);
            hooksConfig = hooksConfig.setShouldCallAfterRemoveLiquidity(hookFlags.shouldCallAfterRemoveLiquidity);
            hooksConfig = hooksConfig.setHooksContract(params.poolHooksContract);

            _hooksConfigBits[pool] = hooksConfig;
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

            bool hasRateProvider = tokenData.rateProvider != IRateProvider(address(0));

            _poolTokenInfo[pool][token] = TokenInfo({
                tokenType: tokenData.tokenType,
                rateProvider: tokenData.rateProvider,
                paysYieldFees: tokenData.paysYieldFees
            });

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
        {
            // Initialize the pool-specific protocol fee values to the current global defaults.
            (uint256 aggregateSwapFeePercentage, uint256 aggregateYieldFeePercentage) = _protocolFeeController
                .registerPool(pool, params.roleAccounts.poolCreator, params.protocolFeeExempt);

            PoolConfigBits poolConfigBits = _poolConfigBits[pool];

            poolConfigBits = poolConfigBits.setPoolRegistered(true);
            poolConfigBits = poolConfigBits.setDisableUnbalancedLiquidity(
                params.liquidityManagement.disableUnbalancedLiquidity
            );
            poolConfigBits = poolConfigBits.setAddLiquidityCustom(params.liquidityManagement.enableAddLiquidityCustom);
            poolConfigBits = poolConfigBits.setRemoveLiquidityCustom(
                params.liquidityManagement.enableRemoveLiquidityCustom
            );
            poolConfigBits = poolConfigBits.setDonation(params.liquidityManagement.enableDonation);
            poolConfigBits = poolConfigBits.setTokenDecimalDiffs(PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs));
            poolConfigBits = poolConfigBits.setPauseWindowEndTime(params.pauseWindowEndTime);
            poolConfigBits = poolConfigBits.setAggregateSwapFeePercentage(aggregateSwapFeePercentage);
            poolConfigBits = poolConfigBits.setAggregateYieldFeePercentage(aggregateYieldFeePercentage);

            _poolConfigBits[pool] = poolConfigBits;
        }

        _setStaticSwapFeePercentage(pool, params.swapFeePercentage);

        // Emit an event to log the pool registration (pass msg.sender as the factory argument)
        emit PoolRegistered(
            pool,
            msg.sender,
            params.tokenConfig,
            params.swapFeePercentage,
            params.pauseWindowEndTime,
            params.roleAccounts,
            hooksConfig.toHooksConfig(),
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
    }

    /// @inheritdoc IVaultExtension
    function initialize(
        address pool,
        address to,
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external onlyVaultDelegateCall onlyWhenUnlocked withRegisteredPool(pool) returns (uint256 bptAmountOut) {
        _ensureUnpaused(pool);
        HooksConfigBits hooksConfig = _hooksConfigBits[pool];

        // Balances are zero until after initialize is callled, so there is no need to charge pending yield fee here.
        PoolData memory poolData = _loadPoolData(pool, Rounding.ROUND_DOWN);

        if (poolData.poolConfigBits.isPoolInitialized()) {
            revert PoolAlreadyInitialized(pool);
        }
        uint256 numTokens = poolData.tokens.length;

        InputHelpers.ensureInputLengthMatch(numTokens, exactAmountsIn.length);

        // Amounts are entering pool math, so round down. A lower invariant after the join means less bptOut,
        // favoring the pool.
        uint256[] memory exactAmountsInScaled18 = exactAmountsIn.copyToScaled18ApplyRateRoundDownArray(
            poolData.decimalScalingFactors,
            poolData.tokenRates
        );

        if (hooksConfig.callBeforeInitializeHook(exactAmountsInScaled18, userData)) {
            // The before hook is reentrant, and could have changed token rates.
            // Updating balances here is unnecessary since they're 0, but we do not special case before init
            // for the sake of bytecode size.
            poolData.reloadBalancesAndRates(_poolTokenBalances[pool], Rounding.ROUND_DOWN);

            // Also update exactAmountsInScaled18, in case the underlying rates changed.
            exactAmountsInScaled18 = exactAmountsIn.copyToScaled18ApplyRateRoundDownArray(
                poolData.decimalScalingFactors,
                poolData.tokenRates
            );
        }

        bptAmountOut = _initialize(pool, to, poolData, tokens, exactAmountsIn, exactAmountsInScaled18, minBptAmountOut);

        hooksConfig.callAfterInitializeHook(exactAmountsInScaled18, bptAmountOut, userData);
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

        for (uint256 i = 0; i < poolData.tokens.length; ++i) {
            IERC20 actualToken = poolData.tokens[i];

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

        emit PoolBalanceChanged(pool, to, exactAmountsIn.unsafeCastToInt256(true));

        poolData.poolConfigBits = poolData.poolConfigBits.setPoolInitialized(true);

        // Store config and mark the pool as initialized
        _poolConfigBits[pool] = poolData.poolConfigBits;

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
    function isPoolInitialized(
        address pool
    ) external view onlyVaultDelegateCall withRegisteredPool(pool) returns (bool) {
        return _isPoolInitialized(pool);
    }

    /// @inheritdoc IVaultExtension
    function getPoolConfig(
        address pool
    ) external view onlyVaultDelegateCall withRegisteredPool(pool) returns (PoolConfig memory) {
        PoolConfigBits config = _poolConfigBits[pool];

        return
            PoolConfig({
                isPoolRegistered: config.isPoolRegistered(),
                isPoolInitialized: config.isPoolInitialized(),
                isPoolPaused: config.isPoolPaused(),
                isPoolInRecoveryMode: config.isPoolInRecoveryMode(),
                staticSwapFeePercentage: config.getStaticSwapFeePercentage(),
                aggregateSwapFeePercentage: config.getAggregateSwapFeePercentage(),
                aggregateYieldFeePercentage: config.getAggregateYieldFeePercentage(),
                tokenDecimalDiffs: config.getTokenDecimalDiffs(),
                pauseWindowEndTime: config.getPauseWindowEndTime(),
                liquidityManagement: LiquidityManagement({
                    // NOTE: supportUnbalancedLiquidity is inverted because false means it is supported
                    disableUnbalancedLiquidity: !config.supportsUnbalancedLiquidity(),
                    enableAddLiquidityCustom: config.supportsAddLiquidityCustom(),
                    enableRemoveLiquidityCustom: config.supportsRemoveLiquidityCustom(),
                    enableDonation: config.supportsDonation()
                })
            });
    }

    /// @inheritdoc IVaultExtension
    function getHooksConfig(
        address pool
    ) external view onlyVaultDelegateCall withRegisteredPool(pool) returns (HooksConfig memory) {
        return _hooksConfigBits[pool].toHooksConfig();
    }

    /// @inheritdoc IVaultExtension
    function getPoolTokens(
        address pool
    ) external view onlyVaultDelegateCall withRegisteredPool(pool) returns (IERC20[] memory tokens) {
        // Retrieve the mapping of tokens and their balances for the specified pool.
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances = _poolTokenBalances[pool];
        uint256 numTokens = poolTokenBalances.length();
        // Initialize arrays to store tokens based on the number of tokens in the pool.
        tokens = new IERC20[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length,
            // we can safely use `unchecked_at`. This ensures that `i` is a valid token index and minimizes
            // storage reads.
            tokens[i] = poolTokenBalances.unchecked_keyAt(i);
        }
    }

    /// @inheritdoc IVaultExtension
    function getPoolTokenRates(
        address pool
    )
        external
        view
        onlyVaultDelegateCall
        withRegisteredPool(pool)
        returns (uint256[] memory decimalScalingFactors, uint256[] memory tokenRates)
    {
        // Retrieve the mapping of tokens and their balances for the specified pool.
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances = _poolTokenBalances[pool];
        uint256 numTokens = poolTokenBalances.length();
        PoolConfigBits poolConfig = _poolConfigBits[pool];

        decimalScalingFactors = PoolConfigLib.getDecimalScalingFactors(poolConfig, numTokens);
        tokenRates = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length,
            // we can safely use `unchecked_at`. This ensures that `i` is a valid token index and minimizes
            // storage reads.
            IERC20 token = poolTokenBalances.unchecked_keyAt(i);
            TokenInfo memory tokenInfo = _poolTokenInfo[pool][token];
            tokenRates[i] = PoolDataLib.getTokenRate(tokenInfo);
        }
    }

    /// @inheritdoc IVaultExtension
    function getPoolData(
        address pool
    ) external view onlyVaultDelegateCall withInitializedPool(pool) returns (PoolData memory) {
        return _loadPoolData(pool, Rounding.ROUND_DOWN);
    }

    /// @inheritdoc IVaultExtension
    function getPoolTokenInfo(
        address pool
    )
        external
        view
        onlyVaultDelegateCall
        withRegisteredPool(pool)
        returns (
            IERC20[] memory tokens,
            TokenInfo[] memory tokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory lastLiveBalances
        )
    {
        // Retrieve the mapping of tokens and their balances for the specified pool.
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances = _poolTokenBalances[pool];
        uint256 numTokens = poolTokenBalances.length();
        tokens = new IERC20[](numTokens);
        tokenInfo = new TokenInfo[](numTokens);
        balancesRaw = new uint256[](numTokens);
        lastLiveBalances = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            bytes32 packedBalance;
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length,
            // we can safely use `unchecked_at`. This ensures that `i` is a valid token index and minimizes
            // storage reads.
            (tokens[i], packedBalance) = poolTokenBalances.unchecked_at(i);
            tokenInfo[i] = _poolTokenInfo[pool][tokens[i]];
            balancesRaw[i] = packedBalance.getBalanceRaw();
            lastLiveBalances[i] = packedBalance.getBalanceDerived();
        }
    }

    /// @inheritdoc IVaultExtension
    function getCurrentLiveBalances(
        address pool
    ) external view onlyVaultDelegateCall withRegisteredPool(pool) returns (uint256[] memory balancesLiveScaled18) {
        return _loadPoolData(pool, Rounding.ROUND_DOWN).balancesLiveScaled18;
    }

    /// @inheritdoc IVaultExtension
    function computeDynamicSwapFee(
        address pool,
        IBasePool.PoolSwapParams memory swapParams
    ) external view onlyVaultDelegateCall withRegisteredPool(pool) returns (bool success, uint256 dynamicSwapFee) {
        return
            _hooksConfigBits[pool].callComputeDynamicSwapFeeHook(
                swapParams,
                _poolConfigBits[pool].getStaticSwapFeePercentage()
            );
    }

    /// @inheritdoc IVaultExtension
    function getBptRate(
        address pool
    ) external view onlyVaultDelegateCall withRegisteredPool(pool) returns (uint256 rate) {
        PoolData memory poolData = _loadPoolData(pool, Rounding.ROUND_DOWN);
        uint256 invariant = IBasePool(pool).computeInvariant(poolData.balancesLiveScaled18);

        return invariant.divDown(_totalSupply(pool));
    }

    /*******************************************************************************
                                    Pool Tokens
    *******************************************************************************/

    /// @inheritdoc IVaultExtension
    function totalSupply(address token) external view onlyVaultDelegateCall returns (uint256) {
        return _totalSupply(token);
    }

    /// @inheritdoc IVaultExtension
    function balanceOf(address token, address account) external view onlyVaultDelegateCall returns (uint256) {
        return _balanceOf(token, account);
    }

    /// @inheritdoc IVaultExtension
    function allowance(
        address token,
        address owner,
        address spender
    ) external view onlyVaultDelegateCall returns (uint256) {
        return _allowance(token, owner, spender);
    }

    /// @inheritdoc IVaultExtension
    function transfer(address owner, address to, uint256 amount) external onlyVaultDelegateCall returns (bool) {
        _transfer(msg.sender, owner, to, amount);
        return true;
    }

    /// @inheritdoc IVaultExtension
    function approve(address owner, address spender, uint256 amount) external onlyVaultDelegateCall returns (bool) {
        _approve(msg.sender, owner, spender, amount);
        return true;
    }

    /// @inheritdoc IVaultExtension
    function transferFrom(
        address spender,
        address from,
        address to,
        uint256 amount
    ) external onlyVaultDelegateCall returns (bool) {
        _spendAllowance(msg.sender, from, spender, amount);
        _transfer(msg.sender, from, to, amount);
        return true;
    }

    /*******************************************************************************
                                     Pool Pausing
    *******************************************************************************/

    /// @inheritdoc IVaultExtension
    function isPoolPaused(address pool) external view onlyVaultDelegateCall withRegisteredPool(pool) returns (bool) {
        return _isPoolPaused(pool);
    }

    /// @inheritdoc IVaultExtension
    function getPoolPausedState(
        address pool
    ) external view onlyVaultDelegateCall withRegisteredPool(pool) returns (bool, uint32, uint32, address) {
        (bool paused, uint32 pauseWindowEndTime) = _getPoolPausedState(pool);

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

    // Swap and Yield fees are both stored using the PackedTokenBalance library, which is usually used for
    // balances that are related (e.g., raw and live). In this case, it holds two uncorrelated values: swap
    // and yield fee amounts, arbitrarily assigning "Raw" to Swap and "Derived" to Yield.

    /// @inheritdoc IVaultExtension
    function getAggregateSwapFeeAmount(
        address pool,
        IERC20 token
    ) external view onlyVaultDelegateCall withRegisteredPool(pool) returns (uint256) {
        return _aggregateFeeAmounts[pool][token].getBalanceRaw();
    }

    /// @inheritdoc IVaultExtension
    function getAggregateYieldFeeAmount(
        address pool,
        IERC20 token
    ) external view onlyVaultDelegateCall withRegisteredPool(pool) returns (uint256) {
        return _aggregateFeeAmounts[pool][token].getBalanceDerived();
    }

    /// @inheritdoc IVaultExtension
    function getStaticSwapFeePercentage(
        address pool
    ) external view onlyVaultDelegateCall withRegisteredPool(pool) returns (uint256) {
        PoolConfigBits config = _poolConfigBits[pool];
        return config.getStaticSwapFeePercentage();
    }

    /// @inheritdoc IVaultExtension
    function getPoolRoleAccounts(
        address pool
    ) external view onlyVaultDelegateCall withRegisteredPool(pool) returns (PoolRoleAccounts memory) {
        return _poolRoleAccounts[pool];
    }

    /*******************************************************************************
                                    Recovery Mode
    *******************************************************************************/

    /// @inheritdoc IVaultExtension
    function isPoolInRecoveryMode(
        address pool
    ) external view onlyVaultDelegateCall withRegisteredPool(pool) returns (bool) {
        return _isPoolInRecoveryMode(pool);
    }

    /// @inheritdoc IVaultExtension
    function removeLiquidityRecovery(
        address pool,
        address from,
        uint256 exactBptAmountIn
    )
        external
        onlyVaultDelegateCall
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
            balancesRaw[i] = packedBalances.getBalanceRaw();
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
            poolBalances.unchecked_setAt(i, packedBalances.setBalanceRaw(balancesRaw[i]));
        }

        _spendAllowance(address(pool), from, msg.sender, exactBptAmountIn);

        // When removing liquidity, we must burn tokens concurrently with updating pool balances,
        // as the pool's math relies on totalSupply.
        // Burning will be reverted if it results in a total supply less than the _MINIMUM_TOTAL_SUPPLY.
        _burn(address(pool), from, exactBptAmountIn);

        emit PoolBalanceChanged(
            pool,
            from,
            // We can unsafely cast to int256 because balances are stored as uint128 (see PackedTokenBalance).
            amountsOutRaw.unsafeCastToInt256(false)
        );
    }

    /*******************************************************************************
                                        Queries
    *******************************************************************************/

    /// @dev Ensure that only static calls are made to the functions with this modifier.
    modifier query() {
        _setupQuery();
        _;
    }

    function _setupQuery() internal {
        if (EVMCallModeHelpers.isStaticCall() == false) {
            revert EVMCallModeHelpers.NotStaticCall();
        }

        bool _isQueryDisabled = _vaultStateBits.isQueryDisabled();
        if (_isQueryDisabled) {
            revert QueriesDisabled();
        }

        // Unlock so that `onlyWhenUnlocked` does not revert
        _isUnlocked().tstore(true);
    }

    /// @inheritdoc IVaultExtension
    function quote(bytes calldata data) external payable query onlyVaultDelegateCall returns (bytes memory result) {
        // Forward the incoming call to the original sender of this transaction.
        return (msg.sender).functionCallWithValue(data, msg.value);
    }

    /// @inheritdoc IVaultExtension
    function quoteAndRevert(bytes calldata data) external payable query onlyVaultDelegateCall {
        // Forward the incoming call to the original sender of this transaction.
        (bool success, bytes memory result) = (msg.sender).call{ value: msg.value }(data);
        if (success) {
            // This will only revert if result is empty and sender account has no code.
            Address.verifyCallResultFromTarget(msg.sender, success, result);
            // Send result in revert reason.
            revert RevertCodec.Result(result);
        } else {
            // If the call reverted with a spoofed `QuoteResult`, we catch it and bubble up a different reason.
            bytes4 errorSelector = RevertCodec.parseSelector(result);
            if (errorSelector == RevertCodec.Result.selector) {
                revert QuoteResultSpoofed();
            }

            // Otherwise we bubble up the original revert reason.
            RevertCodec.bubbleUpRevert(result);
        }
    }

    /// @inheritdoc IVaultExtension
    function calculateBufferAmounts(
        SwapKind kind,
        IERC4626 wrappedToken,
        uint256 amountGiven
    )
        external
        query
        onlyVaultDelegateCall
        returns (uint256 amountCalculated, uint256 amountInUnderlying, uint256 amountOutWrapped)
    {
        IERC20 underlyingToken = IERC20(wrappedToken.asset());
        // Uses the most accurate calculation so that a query matches the actual operation
        if (kind == SwapKind.EXACT_IN) {
            amountCalculated = wrappedToken.previewDeposit(amountGiven);
            (amountInUnderlying, amountOutWrapped) = (amountGiven, amountCalculated);
        } else {
            amountCalculated = wrappedToken.previewMint(amountGiven);
            (amountInUnderlying, amountOutWrapped) = (amountCalculated, amountGiven);
        }
        _takeDebt(underlyingToken, amountInUnderlying);
        _supplyCredit(wrappedToken, amountOutWrapped);
    }

    /// @inheritdoc IVaultExtension
    function isQueryDisabled() external view onlyVaultDelegateCall returns (bool) {
        return _vaultStateBits.isQueryDisabled();
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
