// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultMainMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMainMock.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    TransientStorageHelpers,
    TokenDeltaMappingSlotType
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";
import { StorageSlotExtension } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";
import { InputHelpersMock } from "@balancer-labs/v3-solidity-utils/contracts/test/InputHelpersMock.sol";
import { PackedTokenBalance } from "@balancer-labs/v3-solidity-utils/contracts/helpers/PackedTokenBalance.sol";
import { BufferHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/BufferHelpers.sol";

import { VaultStateLib, VaultStateBits } from "../lib/VaultStateLib.sol";
import { PoolConfigLib, PoolConfigBits } from "../lib/PoolConfigLib.sol";
import { HooksConfigLib } from "../lib/HooksConfigLib.sol";
import { PoolFactoryMock } from "./PoolFactoryMock.sol";
import { Vault } from "../Vault.sol";
import { VaultExtension } from "../VaultExtension.sol";
import { PoolDataLib } from "../lib/PoolDataLib.sol";

struct SwapInternalStateLocals {
    SwapParams params;
    SwapState swapState;
    PoolData poolData;
    VaultState vaultState;
}

contract VaultMock is IVaultMainMock, Vault {
    using PackedTokenBalance for bytes32;
    using PoolConfigLib for PoolConfigBits;
    using HooksConfigLib for PoolConfigBits;
    using VaultStateLib for VaultStateBits;
    using BufferHelpers for bytes32;
    using PoolDataLib for PoolData;
    using TransientStorageHelpers for *;
    using StorageSlotExtension for *;

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
            _getDefaultLiquidityManagement()
        );
    }

    function manualRegisterPoolWithSwapFee(
        address pool,
        IERC20[] memory tokens,
        uint256 swapFeePercentage
    ) external whenVaultNotPaused {
        LiquidityManagement memory liquidityManagement = _getDefaultLiquidityManagement();
        liquidityManagement.disableUnbalancedLiquidity = true;

        _poolFactoryMock.registerPoolWithSwapFee(
            pool,
            buildTokenConfig(tokens),
            swapFeePercentage,
            address(0), // No hook contract
            liquidityManagement
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
            _getDefaultLiquidityManagement()
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
            _getDefaultLiquidityManagement()
        );
    }

    function manualSetPoolRegistered(address pool, bool status) public {
        _poolConfigBits[pool] = _poolConfigBits[pool].setPoolRegistered(status);
    }

    function manualSetIsUnlocked(bool status) public {
        _isUnlocked().tstore(status);
    }

    function manualSetInitializedPool(address pool, bool isPoolInitialized) public {
        _poolConfigBits[pool] = _poolConfigBits[pool].setPoolInitialized(isPoolInitialized);
    }

    function manualSetPoolPauseWindowEndTime(address pool, uint32 pauseWindowEndTime) public {
        _poolConfigBits[pool] = _poolConfigBits[pool].setPauseWindowEndTime(pauseWindowEndTime);
    }

    function manualSetPoolPaused(address pool, bool isPoolPaused) public {
        _poolConfigBits[pool] = _poolConfigBits[pool].setPoolPaused(isPoolPaused);
    }

    function manualSetVaultPaused(bool isVaultPaused) public {
        _vaultStateBits = _vaultStateBits.setVaultPaused(isVaultPaused);
    }

    function manualSetVaultState(bool isVaultPaused, bool isQueryDisabled) public {
        _vaultStateBits = _vaultStateBits.setVaultPaused(isVaultPaused).setQueryDisabled(isQueryDisabled);
    }

    function manualSetPoolConfig(address pool, PoolConfig memory config) public {
        PoolConfigBits poolConfigBits = _poolConfigBits[pool];

        poolConfigBits = poolConfigBits.setPoolRegistered(config.isPoolRegistered);
        poolConfigBits = poolConfigBits.setPoolInitialized(config.isPoolInitialized);
        poolConfigBits = poolConfigBits.setPoolInRecoveryMode(config.isPoolInRecoveryMode);
        poolConfigBits = poolConfigBits.setPoolPaused(config.isPoolPaused);
        poolConfigBits = poolConfigBits.setStaticSwapFeePercentage(config.staticSwapFeePercentage);
        poolConfigBits = poolConfigBits.setAggregateSwapFeePercentage(config.aggregateSwapFeePercentage);
        poolConfigBits = poolConfigBits.setAggregateYieldFeePercentage(config.aggregateYieldFeePercentage);
        poolConfigBits = poolConfigBits.setTokenDecimalDiffs(config.tokenDecimalDiffs);
        poolConfigBits = poolConfigBits.setPauseWindowEndTime(config.pauseWindowEndTime);
        poolConfigBits = poolConfigBits.setDisableUnbalancedLiquidity(
            config.liquidityManagement.disableUnbalancedLiquidity
        );
        poolConfigBits = poolConfigBits.setAddLiquidityCustom(config.liquidityManagement.enableAddLiquidityCustom);
        poolConfigBits = poolConfigBits.setRemoveLiquidityCustom(
            config.liquidityManagement.enableRemoveLiquidityCustom
        );
        poolConfigBits = poolConfigBits.setDonation(config.liquidityManagement.enableDonation);

        _poolConfigBits[pool] = poolConfigBits;
    }

    function manualSetStaticSwapFeePercentage(address pool, uint256 value) public {
        _setStaticSwapFeePercentage(pool, value);
    }

    function manualUnsafeSetStaticSwapFeePercentage(address pool, uint256 value) public {
        _poolConfigBits[pool] = _poolConfigBits[pool].setStaticSwapFeePercentage(value);
    }

    function manualSetHooksConfig(address pool, HooksConfig memory hooksConfig) public {
        PoolConfigBits poolConfigBits = _poolConfigBits[pool];

        poolConfigBits = poolConfigBits.setHookAdjustedAmounts(hooksConfig.enableHookAdjustedAmounts);
        poolConfigBits = poolConfigBits.setShouldCallBeforeInitialize(hooksConfig.shouldCallBeforeInitialize);
        poolConfigBits = poolConfigBits.setShouldCallAfterInitialize(hooksConfig.shouldCallAfterInitialize);
        poolConfigBits = poolConfigBits.setShouldCallComputeDynamicSwapFee(hooksConfig.shouldCallComputeDynamicSwapFee);
        poolConfigBits = poolConfigBits.setShouldCallBeforeSwap(hooksConfig.shouldCallBeforeSwap);
        poolConfigBits = poolConfigBits.setShouldCallAfterSwap(hooksConfig.shouldCallAfterSwap);
        poolConfigBits = poolConfigBits.setShouldCallBeforeAddLiquidity(hooksConfig.shouldCallBeforeAddLiquidity);
        poolConfigBits = poolConfigBits.setShouldCallAfterAddLiquidity(hooksConfig.shouldCallAfterAddLiquidity);
        poolConfigBits = poolConfigBits.setShouldCallBeforeRemoveLiquidity(hooksConfig.shouldCallBeforeRemoveLiquidity);
        poolConfigBits = poolConfigBits.setShouldCallAfterRemoveLiquidity(hooksConfig.shouldCallAfterRemoveLiquidity);

        _poolConfigBits[pool] = poolConfigBits;
        _hooksContracts[pool] = IHooks(hooksConfig.hooksContract);
    }

    function manualSetPoolConfigBits(address pool, PoolConfigBits config) public {
        _poolConfigBits[pool] = config;
    }

    function manualSetPoolTokenInfo(address pool, TokenConfig[] memory tokenConfig) public {
        for (uint256 i = 0; i < tokenConfig.length; ++i) {
            _poolTokenInfo[pool][tokenConfig[i].token] = TokenInfo({
                tokenType: tokenConfig[i].tokenType,
                rateProvider: tokenConfig[i].rateProvider,
                paysYieldFees: tokenConfig[i].paysYieldFees
            });
        }
    }

    function manualSetPoolTokenInfo(address pool, IERC20[] memory tokens, TokenInfo[] memory tokenInfo) public {
        for (uint256 i = 0; i < tokens.length; ++i) {
            _poolTokenInfo[pool][tokens[i]] = tokenInfo[i];
        }
    }

    function manualSetPoolTokensAndBalances(
        address pool,
        IERC20[] memory tokens,
        uint256[] memory tokenBalanceRaw,
        uint256[] memory tokenBalanceLiveScaled18
    ) public {
        require(tokens.length == tokenBalanceRaw.length, "VaultMock: TOKENS_LENGTH_MISMATCH");
        require(tokens.length == tokenBalanceLiveScaled18.length, "VaultMock: TOKENS_LENGTH_MISMATCH");

        mapping(uint256 => bytes32) storage poolTokenBalances = _poolTokenBalances[pool];
        for (uint256 i = 0; i < tokens.length; ++i) {
            poolTokenBalances[i] = PackedTokenBalance.toPackedBalance(tokenBalanceRaw[i], tokenBalanceLiveScaled18[i]);
        }

        _poolTokens[pool] = tokens;
    }

    function manualSetPoolBalances(
        address pool,
        uint256[] memory tokenBalanceRaw,
        uint256[] memory tokenBalanceLiveScaled18
    ) public {
        IERC20[] memory tokens = _poolTokens[pool];

        require(tokens.length == tokenBalanceRaw.length, "VaultMock: TOKENS_LENGTH_MISMATCH");
        require(tokens.length == tokenBalanceLiveScaled18.length, "VaultMock: TOKENS_LENGTH_MISMATCH");

        mapping(uint256 => bytes32) storage poolTokenBalances = _poolTokenBalances[pool];
        for (uint256 i = 0; i < tokens.length; ++i) {
            poolTokenBalances[i] = PackedTokenBalance.toPackedBalance(tokenBalanceRaw[i], tokenBalanceLiveScaled18[i]);
        }
    }

    function mockIsUnlocked() public view onlyWhenUnlocked {}

    function mockWithInitializedPool(address pool) public view withInitializedPool(pool) {}

    function ensurePoolNotPaused(address pool) public view {
        _ensurePoolNotPaused(pool);
    }

    function ensureUnpausedAndGetVaultState(address pool) public view returns (VaultState memory vaultState) {
        _ensureUnpaused(pool);
        VaultStateBits state = _vaultStateBits;
        vaultState = VaultState({
            isQueryDisabled: state.isQueryDisabled(),
            isVaultPaused: state.isVaultPaused(),
            areBuffersPaused: state.areBuffersPaused()
        });
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

    function recoveryModeExit(address pool) external view onlyInRecoveryMode(pool) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function loadPoolDataUpdatingBalancesAndYieldFees(
        address pool,
        Rounding roundingDirection
    ) external returns (PoolData memory) {
        return _loadPoolDataUpdatingBalancesAndYieldFees(pool, roundingDirection);
    }

    function loadPoolDataUpdatingBalancesAndYieldFeesReentrancy(
        address pool,
        Rounding roundingDirection
    ) external nonReentrant returns (PoolData memory) {
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
        return PoolDataLib._computeYieldFeesDue(poolData, lastLiveBalance, tokenIndex, aggregateYieldFeePercentage);
    }

    function getRawBalances(address pool) external view returns (uint256[] memory balancesRaw) {
        mapping(uint256 => bytes32) storage poolTokenBalances = _poolTokenBalances[pool];

        uint256 numTokens = _poolTokens[pool].length;
        balancesRaw = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            balancesRaw[i] = poolTokenBalances[i].getBalanceRaw();
        }
    }

    function getLastLiveBalances(address pool) external view returns (uint256[] memory lastBalancesLiveScaled18) {
        mapping(uint256 => bytes32) storage poolTokenBalances = _poolTokenBalances[pool];

        uint256 numTokens = _poolTokens[pool].length;
        lastBalancesLiveScaled18 = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            lastBalancesLiveScaled18[i] = poolTokenBalances[i].getBalanceDerived();
        }
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
        _nonZeroDeltaCount().tstore(deltaCount);
    }

    function manualSetReservesOf(IERC20 token, uint256 reserves) external {
        _reservesOf[token] = reserves;
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
        PoolSwapParams memory swapParams = _buildPoolSwapParams(params, state, poolData);

        (amountCalculatedRaw, amountCalculatedScaled18, amountIn, amountOut) = _swap(
            params,
            state,
            poolData,
            swapParams
        );

        return (amountCalculatedRaw, amountCalculatedScaled18, amountIn, amountOut, params, state, poolData);
    }

    function manualReentrancySwap(
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    ) external nonReentrant {
        PoolSwapParams memory swapParams = _buildPoolSwapParams(params, state, poolData);
        _swap(params, state, poolData, swapParams);
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
        _poolConfigBits[pool] = _poolConfigBits[pool].setAggregateSwapFeePercentage(value);
    }

    function manualSetAggregateYieldFeePercentage(address pool, uint256 value) external {
        _poolConfigBits[pool] = _poolConfigBits[pool].setAggregateYieldFeePercentage(value);
    }

    function manualBuildPoolSwapParams(
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    ) external view returns (PoolSwapParams memory) {
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

    function manualReentrancyAddLiquidity(
        PoolData memory poolData,
        AddLiquidityParams memory params,
        uint256[] memory maxAmountsInScaled18
    ) external nonReentrant {
        _addLiquidity(poolData, params, maxAmountsInScaled18);
    }

    function manualRemoveLiquidity(
        PoolData memory poolData,
        RemoveLiquidityParams memory params,
        uint256[] memory minAmountsOutScaled18
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
            minAmountsOutScaled18
        );

        updatedPoolData = poolData;
    }

    function manualReentrancyRemoveLiquidity(
        PoolData memory poolData,
        RemoveLiquidityParams memory params,
        uint256[] memory minAmountsOutScaled18
    ) external nonReentrant {
        _removeLiquidity(poolData, params, minAmountsOutScaled18);
    }

    function internalGetBufferUnderlyingSurplus(IERC4626 wrappedToken) external view returns (uint256) {
        bytes32 bufferBalance = _bufferTokenBalances[wrappedToken];
        return bufferBalance.getBufferUnderlyingSurplus(wrappedToken);
    }

    function internalGetBufferWrappedSurplus(IERC4626 wrappedToken) external view returns (uint256) {
        bytes32 bufferBalance = _bufferTokenBalances[wrappedToken];
        return bufferBalance.getBufferWrappedSurplus(wrappedToken);
    }

    function getBufferTokenBalancesBytes(IERC4626 wrappedToken) external view returns (bytes32) {
        return _bufferTokenBalances[wrappedToken];
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

    function forceUnlock() public {
        _isUnlocked().tstore(true);
    }

    function forceLock() public {
        _isUnlocked().tstore(false);
    }

    function manualGetPoolConfigBits(address pool) external view returns (PoolConfigBits) {
        return _poolConfigBits[pool];
    }

    function manualGetIsUnlocked() external view returns (StorageSlotExtension.BooleanSlotType slot) {
        return _isUnlocked();
    }

    function manualGetNonzeroDeltaCount() external view returns (StorageSlotExtension.Uint256SlotType slot) {
        return _nonZeroDeltaCount();
    }

    function manualGetTokenDeltas() external view returns (TokenDeltaMappingSlotType slot) {
        return _tokenDeltas();
    }

    function manualErc4626BufferWrapOrUnwrapReentrancy(
        BufferWrapOrUnwrapParams memory params
    ) external nonReentrant returns (uint256 amountCalculatedRaw, uint256 amountInRaw, uint256 amountOutRaw) {
        return IVault(address(this)).erc4626BufferWrapOrUnwrap(params);
    }

    function manualSettleReentrancy(IERC20 token) public nonReentrant returns (uint256 paid) {
        return IVault(address(this)).settle(token, 0);
    }

    function manualSendToReentrancy(IERC20 token, address to, uint256 amount) public nonReentrant {
        IVault(address(this)).sendTo(token, to, amount);
    }

    function manualFindTokenIndex(IERC20[] memory tokens, IERC20 token) public pure returns (uint256 index) {
        return _findTokenIndex(tokens, token);
    }

    function _getDefaultLiquidityManagement() private pure returns (LiquidityManagement memory) {
        LiquidityManagement memory liquidityManagement;
        liquidityManagement.enableAddLiquidityCustom = true;
        liquidityManagement.enableRemoveLiquidityCustom = true;
        return liquidityManagement;
    }

    function manualSetPoolCreator(address pool, address newPoolCreator) public {
        _poolRoleAccounts[pool].poolCreator = newPoolCreator;
    }
}
