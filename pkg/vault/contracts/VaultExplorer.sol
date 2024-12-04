// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    TokenInfo,
    PoolRoleAccounts,
    PoolConfig,
    HooksConfig,
    PoolData,
    PoolSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

contract VaultExplorer is IVaultExplorer {
    IVault internal immutable _vault;

    constructor(IVault vault) {
        _vault = vault;
    }

    /***************************************************************************
                                  Vault Contracts
    ***************************************************************************/

    /// @inheritdoc IVaultExplorer
    function getVault() external view returns (address vault) {
        return address(_vault);
    }

    /// @inheritdoc IVaultExplorer
    function getVaultExtension() external view returns (address vaultExtension) {
        return _vault.getVaultExtension();
    }

    /// @inheritdoc IVaultExplorer
    function getVaultAdmin() external view returns (address vaultAdmin) {
        return IVaultExtension(_vault.getVaultExtension()).getVaultAdmin();
    }

    /// @inheritdoc IVaultExplorer
    function getAuthorizer() external view returns (address authorizer) {
        return address(_vault.getAuthorizer());
    }

    /// @inheritdoc IVaultExplorer
    function getProtocolFeeController() external view returns (address protocolFeeController) {
        return address(_vault.getProtocolFeeController());
    }

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function isUnlocked() external view returns (bool unlocked) {
        return _vault.isUnlocked();
    }

    /// @inheritdoc IVaultExplorer
    function getNonzeroDeltaCount() external view returns (uint256 nonzeroDeltaCount) {
        return _vault.getNonzeroDeltaCount();
    }

    /// @inheritdoc IVaultExplorer
    function getTokenDelta(IERC20 token) external view returns (int256 tokenDelta) {
        return _vault.getTokenDelta(token);
    }

    /// @inheritdoc IVaultExplorer
    function getReservesOf(IERC20 token) external view returns (uint256 reserveAmount) {
        return _vault.getReservesOf(token);
    }

    /// @inheritdoc IVaultExplorer
    function getAddLiquidityCalledFlag(address pool) external view returns (bool liquidityAdded) {
        return _vault.getAddLiquidityCalledFlag(pool);
    }

    /*******************************************************************************
                                    Pool Registration
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function isPoolRegistered(address pool) external view returns (bool registered) {
        return _vault.isPoolRegistered(pool);
    }

    /*******************************************************************************
                                    Pool Information
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function isPoolInitialized(address pool) external view returns (bool initialized) {
        return _vault.isPoolInitialized(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolTokens(address pool) external view returns (IERC20[] memory tokens) {
        return _vault.getPoolTokens(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolTokenCountAndIndexOfToken(
        address pool,
        IERC20 token
    ) external view returns (uint256 tokenCount, uint256 index) {
        return _vault.getPoolTokenCountAndIndexOfToken(pool, token);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolTokenRates(
        address pool
    ) external view returns (uint256[] memory decimalScalingFactors, uint256[] memory tokenRates) {
        return _vault.getPoolTokenRates(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolData(address pool) external view returns (PoolData memory poolData) {
        return _vault.getPoolData(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolTokenInfo(
        address pool
    )
        external
        view
        returns (
            IERC20[] memory tokens,
            TokenInfo[] memory tokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory lastBalancesLiveScaled18
        )
    {
        return _vault.getPoolTokenInfo(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getCurrentLiveBalances(address pool) external view returns (uint256[] memory balancesLiveScaled18) {
        return _vault.getCurrentLiveBalances(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolConfig(address pool) external view returns (PoolConfig memory poolConfig) {
        return _vault.getPoolConfig(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getHooksConfig(address pool) external view returns (HooksConfig memory hooksConfig) {
        return _vault.getHooksConfig(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getBptRate(address pool) external view returns (uint256 rate) {
        return _vault.getBptRate(pool);
    }

    /*******************************************************************************
                                 Balancer Pool Tokens
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function totalSupply(address token) external view returns (uint256 tokenTotalSupply) {
        return _vault.totalSupply(token);
    }

    /// @inheritdoc IVaultExplorer
    function balanceOf(address token, address account) external view returns (uint256 tokenBalance) {
        return _vault.balanceOf(token, account);
    }

    /// @inheritdoc IVaultExplorer
    function allowance(address token, address owner, address spender) external view returns (uint256 tokenAllowance) {
        return _vault.allowance(token, owner, spender);
    }

    /*******************************************************************************
                                     Pool Pausing
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function isPoolPaused(address pool) external view returns (bool poolPaused) {
        return _vault.isPoolPaused(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolPausedState(
        address pool
    )
        external
        view
        returns (bool poolPaused, uint32 poolPauseWindowEndTime, uint32 poolBufferPeriodEndTime, address pauseManager)
    {
        return _vault.getPoolPausedState(pool);
    }

    /*******************************************************************************
                                        Fees
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function getAggregateSwapFeeAmount(address pool, IERC20 token) external view returns (uint256 swapFeeAmount) {
        return _vault.getAggregateSwapFeeAmount(pool, token);
    }

    /// @inheritdoc IVaultExplorer
    function getAggregateYieldFeeAmount(address pool, IERC20 token) external view returns (uint256 yieldFeeAmount) {
        return _vault.getAggregateYieldFeeAmount(pool, token);
    }

    /// @inheritdoc IVaultExplorer
    function getStaticSwapFeePercentage(address pool) external view returns (uint256 swapFeePercentage) {
        return _vault.getStaticSwapFeePercentage(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolRoleAccounts(address pool) external view returns (PoolRoleAccounts memory roleAccounts) {
        return _vault.getPoolRoleAccounts(pool);
    }

    /// @inheritdoc IVaultExplorer
    function computeDynamicSwapFeePercentage(
        address pool,
        PoolSwapParams memory swapParams
    ) external view returns (uint256 dynamicSwapFeePercentage) {
        return _vault.computeDynamicSwapFeePercentage(pool, swapParams);
    }

    /*******************************************************************************
                                    Recovery Mode
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function isPoolInRecoveryMode(address pool) external view returns (bool inRecoveryMode) {
        return _vault.isPoolInRecoveryMode(pool);
    }

    /*******************************************************************************
                                    Queries
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function isQueryDisabled() external view returns (bool queryDisabled) {
        return _vault.isQueryDisabled();
    }

    /// @inheritdoc IVaultExplorer
    function isQueryDisabledPermanently() external view returns (bool queryDisabledPermanently) {
        return _vault.isQueryDisabledPermanently();
    }

    /***************************************************************************
                              Vault Admin Functions
    ***************************************************************************/

    /// @inheritdoc IVaultExplorer
    function getPauseWindowEndTime() external view returns (uint32 pauseWindowEndTime) {
        return _vault.getPauseWindowEndTime();
    }

    /// @inheritdoc IVaultExplorer
    function getBufferPeriodDuration() external view returns (uint32 bufferPeriodDuration) {
        return _vault.getBufferPeriodDuration();
    }

    /// @inheritdoc IVaultExplorer
    function getBufferPeriodEndTime() external view returns (uint32 bufferPeriodEndTime) {
        return _vault.getBufferPeriodEndTime();
    }

    /// @inheritdoc IVaultExplorer
    function getMinimumPoolTokens() external view returns (uint256 minTokens) {
        return _vault.getMinimumPoolTokens();
    }

    /// @inheritdoc IVaultExplorer
    function getMaximumPoolTokens() external view returns (uint256 maxTokens) {
        return _vault.getMaximumPoolTokens();
    }

    /// @inheritdoc IVaultExplorer
    function getMinimumTradeAmount() external view returns (uint256 minimumTradeAmount) {
        return _vault.getMinimumTradeAmount();
    }

    /// @inheritdoc IVaultExplorer
    function getMinimumWrapAmount() external view returns (uint256 minimumWrapAmount) {
        return _vault.getMinimumWrapAmount();
    }

    /// @inheritdoc IVaultExplorer
    function getPoolMinimumTotalSupply() external view returns (uint256 poolMinimumTotalSupply) {
        return _vault.getPoolMinimumTotalSupply();
    }

    /// @inheritdoc IVaultExplorer
    function getBufferMinimumTotalSupply() external view returns (uint256 bufferMinimumTotalSupply) {
        return _vault.getBufferMinimumTotalSupply();
    }

    /*******************************************************************************
                                    Vault Pausing
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function isVaultPaused() external view returns (bool vaultPaused) {
        return _vault.isVaultPaused();
    }

    /// @inheritdoc IVaultExplorer
    function getVaultPausedState()
        external
        view
        returns (bool vaultPaused, uint32 vaultPauseWindowEndTime, uint32 vaultBufferPeriodEndTime)
    {
        return _vault.getVaultPausedState();
    }

    /*******************************************************************************
                                        Fees
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function getAggregateFeePercentages(
        address pool
    ) external view returns (uint256 aggregateSwapFeePercentage, uint256 aggregateYieldFeePercentage) {
        PoolConfig memory poolConfig = _vault.getPoolConfig(pool);

        return (poolConfig.aggregateSwapFeePercentage, poolConfig.aggregateYieldFeePercentage);
    }

    /// @inheritdoc IVaultExplorer
    function collectAggregateFees(address pool) external {
        _vault.getProtocolFeeController().collectAggregateFees(pool);
    }

    /*******************************************************************************
                                  ERC4626 Buffers
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function areBuffersPaused() external view returns (bool buffersPaused) {
        return _vault.areBuffersPaused();
    }

    /// @inheritdoc IVaultExplorer
    function getBufferAsset(IERC4626 wrappedToken) external view returns (address underlyingToken) {
        return _vault.getBufferAsset(wrappedToken);
    }

    /// @inheritdoc IVaultExplorer
    function getBufferOwnerShares(
        IERC4626 wrappedToken,
        address liquidityOwner
    ) external view returns (uint256 ownerShares) {
        return _vault.getBufferOwnerShares(wrappedToken, liquidityOwner);
    }

    /// @inheritdoc IVaultExplorer
    function getBufferTotalShares(IERC4626 wrappedToken) external view returns (uint256 bufferShares) {
        return _vault.getBufferTotalShares(wrappedToken);
    }

    /// @inheritdoc IVaultExplorer
    function getBufferBalance(
        IERC4626 wrappedToken
    ) external view returns (uint256 underlyingBalanceRaw, uint256 wrappedBalanceRaw) {
        return _vault.getBufferBalance(wrappedToken);
    }
}
