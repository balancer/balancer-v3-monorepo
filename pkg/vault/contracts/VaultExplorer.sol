// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultExplorer } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExplorer.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
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
    function getVault() external view returns (address) {
        return address(_vault);
    }

    /// @inheritdoc IVaultExplorer
    function getVaultExtension() external view returns (address) {
        return _vault.getVaultExtension();
    }

    /// @inheritdoc IVaultExplorer
    function getVaultAdmin() external view returns (address) {
        return IVaultExtension(_vault.getVaultExtension()).getVaultAdmin();
    }

    /// @inheritdoc IVaultExplorer
    function getAuthorizer() external view returns (address) {
        return address(_vault.getAuthorizer());
    }

    /// @inheritdoc IVaultExplorer
    function getProtocolFeeController() external view returns (address) {
        return address(_vault.getProtocolFeeController());
    }

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function isUnlocked() external view returns (bool) {
        return _vault.isUnlocked();
    }

    /// @inheritdoc IVaultExplorer
    function getNonzeroDeltaCount() external view returns (uint256) {
        return _vault.getNonzeroDeltaCount();
    }

    /// @inheritdoc IVaultExplorer
    function getTokenDelta(IERC20 token) external view returns (int256) {
        return _vault.getTokenDelta(token);
    }

    /// @inheritdoc IVaultExplorer
    function getReservesOf(IERC20 token) external view returns (uint256) {
        return _vault.getReservesOf(token);
    }

    /*******************************************************************************
                                    Pool Registration
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function isPoolRegistered(address pool) external view returns (bool) {
        return _vault.isPoolRegistered(pool);
    }

    /*******************************************************************************
                                    Pool Information
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function isPoolInitialized(address pool) external view returns (bool) {
        return _vault.isPoolInitialized(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolConfig(address pool) external view returns (PoolConfig memory) {
        return _vault.getPoolConfig(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getHooksConfig(address pool) external view returns (HooksConfig memory) {
        return _vault.getHooksConfig(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolTokens(address pool) external view returns (IERC20[] memory) {
        return _vault.getPoolTokens(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolTokenCountAndIndexOfToken(address pool, IERC20 token) external view returns (uint256, uint256) {
        return _vault.getPoolTokenCountAndIndexOfToken(pool, token);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolTokenRates(address pool) external view returns (uint256[] memory, uint256[] memory) {
        return _vault.getPoolTokenRates(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolData(address pool) external view returns (PoolData memory) {
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
            uint256[] memory scalingFactors
        )
    {
        return _vault.getPoolTokenInfo(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getCurrentLiveBalances(address pool) external view returns (uint256[] memory) {
        return _vault.getCurrentLiveBalances(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getBptRate(address pool) external view returns (uint256) {
        return _vault.getBptRate(pool);
    }

    /*******************************************************************************
                                    Pool Tokens
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function totalSupply(address token) external view returns (uint256) {
        return _vault.totalSupply(token);
    }

    /// @inheritdoc IVaultExplorer
    function balanceOf(address token, address account) external view returns (uint256) {
        return _vault.balanceOf(token, account);
    }

    /// @inheritdoc IVaultExplorer
    function allowance(address token, address owner, address spender) external view returns (uint256) {
        return _vault.allowance(token, owner, spender);
    }

    /*******************************************************************************
                                     Pool Pausing
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function isPoolPaused(address pool) external view returns (bool) {
        return _vault.isPoolPaused(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolPausedState(address pool) external view returns (bool, uint32, uint32, address) {
        return _vault.getPoolPausedState(pool);
    }

    /*******************************************************************************
                                        Fees
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function getAggregateSwapFeeAmount(address pool, IERC20 token) external view returns (uint256) {
        return _vault.getAggregateSwapFeeAmount(pool, token);
    }

    /// @inheritdoc IVaultExplorer
    function getAggregateYieldFeeAmount(address pool, IERC20 token) external view returns (uint256) {
        return _vault.getAggregateYieldFeeAmount(pool, token);
    }

    /// @inheritdoc IVaultExplorer
    function getStaticSwapFeePercentage(address pool) external view returns (uint256) {
        return _vault.getStaticSwapFeePercentage(pool);
    }

    /// @inheritdoc IVaultExplorer
    function getPoolRoleAccounts(address pool) external view returns (PoolRoleAccounts memory) {
        return _vault.getPoolRoleAccounts(pool);
    }

    /// @inheritdoc IVaultExplorer
    function computeDynamicSwapFeePercentage(
        address pool,
        PoolSwapParams memory swapParams
    ) external view returns (bool success, uint256 dynamicSwapFee) {
        return _vault.computeDynamicSwapFeePercentage(pool, swapParams);
    }

    /*******************************************************************************
                                    Recovery Mode
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function isPoolInRecoveryMode(address pool) external view returns (bool) {
        return _vault.isPoolInRecoveryMode(pool);
    }

    /*******************************************************************************
                                    Queries
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function isQueryDisabled() external view returns (bool) {
        return _vault.isQueryDisabled();
    }

    /***************************************************************************
                              Vault Admin Functions
    ***************************************************************************/

    /// @inheritdoc IVaultExplorer
    function getPauseWindowEndTime() external view returns (uint32) {
        return _vault.getPauseWindowEndTime();
    }

    /// @inheritdoc IVaultExplorer
    function getBufferPeriodDuration() external view returns (uint32) {
        return _vault.getBufferPeriodDuration();
    }

    /// @inheritdoc IVaultExplorer
    function getBufferPeriodEndTime() external view returns (uint32) {
        return _vault.getBufferPeriodEndTime();
    }

    /// @inheritdoc IVaultExplorer
    function getMinimumPoolTokens() external view returns (uint256) {
        return _vault.getMinimumPoolTokens();
    }

    /// @inheritdoc IVaultExplorer
    function getMaximumPoolTokens() external view returns (uint256) {
        return _vault.getMaximumPoolTokens();
    }

    /*******************************************************************************
                                    Vault Pausing
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function isVaultPaused() external view returns (bool) {
        return _vault.isVaultPaused();
    }

    /// @inheritdoc IVaultExplorer
    function getVaultPausedState() external view returns (bool, uint32, uint32) {
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
        return _vault.collectAggregateFees(pool);
    }

    /*******************************************************************************
                              Yield-bearing Token Buffers
    *******************************************************************************/

    /// @inheritdoc IVaultExplorer
    function getBufferOwnerShares(IERC4626 token, address user) external view returns (uint256 shares) {
        return _vault.getBufferOwnerShares(token, user);
    }

    /// @inheritdoc IVaultExplorer
    function getBufferTotalShares(IERC4626 token) external view returns (uint256) {
        return _vault.getBufferTotalShares(token);
    }

    /// @inheritdoc IVaultExplorer
    function getBufferBalance(IERC4626 token) external view returns (uint256, uint256) {
        return _vault.getBufferBalance(token);
    }
}
