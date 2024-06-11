// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultMainMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMainMock.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";
import { StorageSlot } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlot.sol";
import { InputHelpersMock } from "@balancer-labs/v3-solidity-utils/contracts/test/InputHelpersMock.sol";

import { PoolConfigLib } from "../lib/PoolConfigLib.sol";
import { HooksConfigLib } from "../lib/HooksConfigLib.sol";
import { PoolFactoryMock } from "./PoolFactoryMock.sol";
import { Vault } from "../Vault.sol";
import { VaultExtension } from "../VaultExtension.sol";
import { PackedTokenBalance } from "../lib/PackedTokenBalance.sol";
import { PoolDataLib } from "../lib/PoolDataLib.sol";
import { BufferPackedTokenBalance } from "../lib/BufferPackedBalance.sol";

struct SwapInternalStateLocals {
    SwapParams params;
    SwapState swapState;
    PoolData poolData;
    VaultState vaultState;
}

contract VaultMock is IVaultMainMock, Vault {
    using EnumerableMap for EnumerableMap.IERC20ToBytes32Map;
    using ScalingHelpers for uint256;
    using PackedTokenBalance for bytes32;
    using PoolConfigLib for PoolConfig;
    using HooksConfigLib for HooksConfig;
    using TransientStorageHelpers for *;
    using StorageSlot for *;
    using PoolDataLib for PoolData;
    using BufferPackedTokenBalance for bytes32;

    PoolFactoryMock private immutable _poolFactoryMock;
    InputHelpersMock private immutable _inputHelpersMock;

    constructor(
        IVaultExtension vaultExtension,
        IAuthorizer authorizer,
        IProtocolFeeController protocolFeeController
    ) Vault(vaultExtension, authorizer, protocolFeeController) {
        uint32 pauseWindowEndTime = IVaultAdmin(address(vaultExtension)).getPauseWindowEndTime();
        uint32 bufferPeriodDuration = IVaultAdmin(address(vaultExtension)).getBufferPeriodDuration();
        _poolFactoryMock = new PoolFactoryMock(IVault(address(this)), pauseWindowEndTime - bufferPeriodDuration);
        _inputHelpersMock = new InputHelpersMock();
    }

    function getPoolFactoryMock() external view returns (address) {
        return address(_poolFactoryMock);
    }

    function burnERC20(address token, address from, uint256 amount) external {
        _burn(token, from, amount);
    }

    function mintERC20(address token, address to, uint256 amount) external {
        _mint(token, to, amount);
    }

    function setConfig(address pool, PoolConfig calldata config) external {
        _poolConfig[pool] = config;
    }

    function setHooksConfig(address pool, HooksConfig calldata config) external {
        _hooksConfig[pool] = config;
    }

    // Used for testing pool registration, which is ordinarily done in the pool factory.
    // The Mock pool has an argument for whether or not to register on deployment. To call register pool
    // separately, deploy it with the registration flag false, then call this function.
    function manualRegisterPool(address pool, IERC20[] memory tokens) external whenVaultNotPaused {
        PoolRoleAccounts memory roleAccounts;

        _poolFactoryMock.registerPool(
            pool,
            buildTokenConfig(tokens),
            roleAccounts,
            address(0), // No hook contract
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: true,
                enableRemoveLiquidityCustom: true
            })
        );
    }

    function manualRegisterPoolWithSwapFee(
        address pool,
        IERC20[] memory tokens,
        uint256 swapFeePercentage
    ) external whenVaultNotPaused {
        _poolFactoryMock.registerPoolWithSwapFee(
            pool,
            buildTokenConfig(tokens),
            swapFeePercentage,
            address(0), // No hook contract
            LiquidityManagement({
                disableUnbalancedLiquidity: true,
                enableAddLiquidityCustom: true,
                enableRemoveLiquidityCustom: true
            })
        );
    }

    function manualRegisterPoolPassThruTokens(address pool, IERC20[] memory tokens) external {
        TokenConfig[] memory tokenConfig = new TokenConfig[](tokens.length);
        PoolRoleAccounts memory roleAccounts;
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokenConfig[i].token = tokens[i];
        }

        _poolFactoryMock.registerPool(
            pool,
            tokenConfig,
            roleAccounts,
            address(0), // No hook contract
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: true,
                enableRemoveLiquidityCustom: true
            })
        );
    }

    function manualRegisterPoolAtTimestamp(
        address pool,
        IERC20[] memory tokens,
        uint32 timestamp,
        PoolRoleAccounts memory roleAccounts
    ) external whenVaultNotPaused {
        _poolFactoryMock.registerPoolAtTimestamp(
            pool,
            buildTokenConfig(tokens),
            timestamp,
            roleAccounts,
            address(0), // No hook contract
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: true,
                enableRemoveLiquidityCustom: true
            })
        );
    }

    function manualSetIsUnlocked(bool status) public {
        _isUnlocked().tstore(status);
    }

    function manualSetInitializedPool(address pool, bool isPoolInitialized) public {
        PoolConfig memory poolConfig = _poolConfig[pool];
        poolConfig.isPoolInitialized = isPoolInitialized;
        _poolConfig[pool] = poolConfig;
    }

    function manualSetPoolPauseWindowEndTime(address pool, uint32 pauseWindowEndTime) public {
        PoolConfig memory poolConfig = _poolConfig[pool];
        poolConfig.pauseWindowEndTime = pauseWindowEndTime;
        _poolConfig[pool] = poolConfig;
    }

    function manualSetPoolPaused(address pool, bool isPoolPaused) public {
        PoolConfig memory poolConfig = _poolConfig[pool];
        poolConfig.isPoolPaused = isPoolPaused;
        _poolConfig[pool] = poolConfig;
    }

    function manualSetVaultPaused(bool isVaultPaused) public {
        _vaultState.isVaultPaused = isVaultPaused;
    }

    function manualSetVaultState(bool isVaultPaused, bool isQueryDisabled) public {
        VaultState memory vaultState = _vaultState;
        vaultState.isVaultPaused = isVaultPaused;
        vaultState.isQueryDisabled = isQueryDisabled;
        _vaultState = vaultState;
    }

    function manualSetPoolConfig(address pool, PoolConfig memory poolConfig) public {
        _poolConfig[pool] = poolConfig;
    }

    function manualSetPoolTokenConfig(address pool, IERC20[] memory tokens, TokenConfig[] memory tokenConfig) public {
        for (uint256 i = 0; i < tokens.length; ++i) {
            _poolTokenConfig[pool][tokens[i]] = tokenConfig[i];
        }
    }

    function manualSetPoolTokenBalances(address pool, IERC20[] memory tokens, uint256[] memory tokenBalanceRaw) public {
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances = _poolTokenBalances[pool];
        for (uint256 i = 0; i < tokens.length; ++i) {
            poolTokenBalances.set(tokens[i], bytes32(tokenBalanceRaw[i]));
        }
    }

    function mockIsUnlocked() public view onlyWhenUnlocked {}

    function mockWithInitializedPool(address pool) public view withInitializedPool(pool) {}

    function ensurePoolNotPaused(address pool) public view {
        _ensurePoolNotPaused(pool);
    }

    function ensureUnpausedAndGetVaultState(address pool) public view returns (VaultState memory vaultState) {
        vaultState = _ensureUnpausedAndGetVaultState(pool);
    }

    function internalGetPoolTokenInfo(
        address pool
    )
        public
        view
        returns (
            TokenConfig[] memory tokenConfig,
            uint256[] memory balancesRaw,
            uint256[] memory decimalScalingFactors,
            PoolConfig memory poolConfig
        )
    {
        PoolData memory poolData = _loadPoolData(pool, Rounding.ROUND_DOWN);
        return (poolData.tokenConfig, poolData.balancesRaw, poolData.decimalScalingFactors, poolData.poolConfig);
    }

    function buildTokenConfig(IERC20[] memory tokens) public view returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokenConfig[i].token = tokens[i];
        }

        tokenConfig = _inputHelpersMock.sortTokenConfig(tokenConfig);
    }

    function buildTokenConfig(
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders
    ) public view returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokenConfig[i].token = tokens[i];
            tokenConfig[i].rateProvider = rateProviders[i];
            tokenConfig[i].tokenType = rateProviders[i] == IRateProvider(address(0))
                ? TokenType.STANDARD
                : TokenType.WITH_RATE;
        }

        tokenConfig = _inputHelpersMock.sortTokenConfig(tokenConfig);
    }

    function buildTokenConfig(
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders,
        bool[] memory yieldFeeFlags
    ) public view returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokenConfig[i].token = tokens[i];
            tokenConfig[i].rateProvider = rateProviders[i];
            tokenConfig[i].tokenType = rateProviders[i] == IRateProvider(address(0))
                ? TokenType.STANDARD
                : TokenType.WITH_RATE;
            tokenConfig[i].paysYieldFees = yieldFeeFlags[i];
        }

        tokenConfig = _inputHelpersMock.sortTokenConfig(tokenConfig);
    }

    function buildTokenConfig(
        IERC20[] memory tokens,
        TokenType[] memory tokenTypes,
        IRateProvider[] memory rateProviders,
        bool[] memory yieldFeeFlags
    ) public view returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokenConfig[i].token = tokens[i];
            tokenConfig[i].tokenType = tokenTypes[i];
            tokenConfig[i].rateProvider = rateProviders[i];
            tokenConfig[i].paysYieldFees = yieldFeeFlags[i];
        }

        tokenConfig = _inputHelpersMock.sortTokenConfig(tokenConfig);
    }

    function getDecimalScalingFactors(address pool) external view returns (uint256[] memory) {
        PoolConfig memory config = _poolConfig[pool];
        IERC20[] memory tokens = _getPoolTokens(pool);

        return PoolConfigLib.getDecimalScalingFactors(config, tokens.length);
    }

    function recoveryModeExit(address pool) external view onlyInRecoveryMode(pool) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function loadPoolDataUpdatingBalancesAndYieldFees(
        address pool,
        Rounding roundingDirection
    ) external returns (PoolData memory) {
        return _loadPoolDataUpdatingBalancesAndYieldFees(pool, roundingDirection);
    }

    function updateLiveTokenBalanceInPoolData(
        PoolData memory poolData,
        uint256 newRawBalance,
        Rounding roundingDirection,
        uint256 tokenIndex
    ) external pure returns (PoolData memory) {
        _updateRawAndLiveTokenBalancesInPoolData(poolData, newRawBalance, roundingDirection, tokenIndex);
        return poolData;
    }

    function computeYieldFeesDue(
        PoolData memory poolData,
        uint256 lastLiveBalance,
        uint256 tokenIndex,
        uint256 aggregateYieldFeePercentage
    ) external pure returns (uint256) {
        return _computeYieldFeesDue(poolData, lastLiveBalance, tokenIndex, aggregateYieldFeePercentage);
    }

    function getRawBalances(address pool) external view returns (uint256[] memory balancesRaw) {
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances = _poolTokenBalances[pool];

        uint256 numTokens = poolTokenBalances.length();
        balancesRaw = new uint256[](numTokens);
        bytes32 packedBalances;

        for (uint256 i = 0; i < numTokens; ++i) {
            (, packedBalances) = poolTokenBalances.unchecked_at(i);
            balancesRaw[i] = packedBalances.getBalanceRaw();
        }
    }

    function getCurrentLiveBalances(address pool) external view returns (uint256[] memory currentLiveBalances) {
        PoolData memory poolData = _loadPoolData(pool, Rounding.ROUND_DOWN);

        return poolData.balancesLiveScaled18;
    }

    function getLastLiveBalances(address pool) external view returns (uint256[] memory lastLiveBalances) {
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances = _poolTokenBalances[pool];

        uint256 numTokens = poolTokenBalances.length();
        lastLiveBalances = new uint256[](numTokens);
        bytes32 packedBalances;

        for (uint256 i = 0; i < numTokens; ++i) {
            (, packedBalances) = poolTokenBalances.unchecked_at(i);
            lastLiveBalances[i] = packedBalances.getBalanceDerived();
        }
    }

    function getMaxConvertError() external pure returns (uint256) {
        return _MAX_CONVERT_ERROR;
    }

    function guardedCheckEntered() external nonReentrant {
        require(reentrancyGuardEntered());
    }

    function unguardedCheckNotEntered() external view {
        require(!reentrancyGuardEntered());
    }

    function accountDelta(IERC20 token, int256 delta) external {
        _accountDelta(token, delta);
    }

    function supplyCredit(IERC20 token, uint256 credit) external {
        _supplyCredit(token, credit);
    }

    function takeDebt(IERC20 token, uint256 debt) external {
        _takeDebt(token, debt);
    }

    function manualSetAccountDelta(IERC20 token, int256 delta) external {
        _tokenDeltas().tSet(token, delta);
    }

    function manualSetNonZeroDeltaCount(uint256 deltaCount) external {
        _nonzeroDeltaCount().tstore(deltaCount);
    }

    function manualInternalSwap(
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    )
        external
        returns (
            uint256 amountCalculatedRaw,
            uint256 amountCalculatedScaled18,
            uint256 amountIn,
            uint256 amountOut,
            SwapParams memory,
            SwapState memory,
            PoolData memory
        )
    {
        IBasePool.PoolSwapParams memory swapParams = _buildPoolSwapParams(params, state, poolData);

        (amountCalculatedRaw, amountCalculatedScaled18, amountIn, amountOut) = _swap(
            params,
            state,
            poolData,
            swapParams
        );

        return (amountCalculatedRaw, amountCalculatedScaled18, amountIn, amountOut, params, state, poolData);
    }

    function manualGetAggregateSwapFeeAmount(address pool, IERC20 token) external view returns (uint256) {
        return _aggregateFeeAmounts[pool][token].getBalanceRaw();
    }

    function manualGetAggregateYieldFeeAmount(address pool, IERC20 token) external view returns (uint256) {
        return _aggregateFeeAmounts[pool][token].getBalanceDerived();
    }

    function manualSetAggregateSwapFeeAmount(address pool, IERC20 token, uint256 value) external {
        _aggregateFeeAmounts[pool][token] = _aggregateFeeAmounts[pool][token].setBalanceRaw(value);
    }

    function manualSetAggregateYieldFeeAmount(address pool, IERC20 token, uint256 value) external {
        _aggregateFeeAmounts[pool][token] = _aggregateFeeAmounts[pool][token].setBalanceDerived(value);
    }

    function manualSetAggregateSwapFeePercentage(address pool, uint256 value) external {
        PoolConfig memory config = _poolConfig[pool];
        config.setAggregateSwapFeePercentage(value);
        _poolConfig[pool] = config;
    }

    function manualSetAggregateYieldFeePercentage(address pool, uint256 value) external {
        PoolConfig memory config = _poolConfig[pool];
        config.setAggregateYieldFeePercentage(value);
        _poolConfig[pool] = config;
    }

    function manualBuildPoolSwapParams(
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    ) external view returns (IBasePool.PoolSwapParams memory) {
        return _buildPoolSwapParams(params, state, poolData);
    }

    function manualComputeAndChargeAggregateSwapFees(
        PoolData memory poolData,
        uint256 swapFeeAmountScaled18,
        address pool,
        IERC20 token,
        uint256 index
    ) external returns (uint256 totalFeesRaw) {
        return _computeAndChargeAggregateSwapFees(poolData, swapFeeAmountScaled18, pool, token, index);
    }

    function manualUpdatePoolDataLiveBalancesAndRates(
        address pool,
        PoolData memory poolData,
        Rounding roundingDirection
    ) external view returns (PoolData memory) {
        poolData.reloadBalancesAndRates(_poolTokenBalances[pool], roundingDirection);

        return poolData;
    }

    function manualAddLiquidity(
        PoolData memory poolData,
        AddLiquidityParams memory params,
        uint256[] memory maxAmountsInScaled18
    )
        external
        returns (
            PoolData memory updatedPoolData,
            uint256[] memory amountsInRaw,
            uint256[] memory amountsInScaled18,
            uint256 bptAmountOut,
            bytes memory returnData
        )
    {
        (amountsInRaw, amountsInScaled18, bptAmountOut, returnData) = _addLiquidity(
            poolData,
            params,
            maxAmountsInScaled18
        );

        updatedPoolData = poolData;
    }

    function manualRemoveLiquidity(
        PoolData memory poolData,
        RemoveLiquidityParams memory params,
        uint256[] memory minAmountsOutScaled18,
        VaultState memory vaultState
    )
        external
        returns (
            PoolData memory updatedPoolData,
            uint256 bptAmountIn,
            uint256[] memory amountsOutRaw,
            uint256[] memory amountsOutScaled18,
            bytes memory returnData
        )
    {
        (bptAmountIn, amountsOutRaw, amountsOutScaled18, returnData) = _removeLiquidity(
            poolData,
            params,
            minAmountsOutScaled18,
            vaultState
        );

        updatedPoolData = poolData;
    }

    function internalGetBufferUnderlyingSurplus(IERC4626 wrappedToken) external view returns (uint256) {
        bytes32 bufferBalance = _bufferTokenBalances[IERC20(address(wrappedToken))];
        return _getBufferUnderlyingSurplus(bufferBalance, wrappedToken);
    }

    function internalGetBufferWrappedSurplus(IERC4626 wrappedToken) external view returns (uint256) {
        bytes32 bufferBalance = _bufferTokenBalances[IERC20(address(wrappedToken))];
        return _getBufferWrappedSurplus(bufferBalance, wrappedToken);
    }

    function manualUpdateReservesAfterWrapping(
        IERC20 underlyingToken,
        IERC20 wrappedToken
    ) external returns (uint256, uint256) {
        return _updateReservesAfterWrapping(underlyingToken, wrappedToken);
    }

    function manualTransfer(IERC20 token, address to, uint256 amount) external {
        token.transfer(to, amount);
    }
}
