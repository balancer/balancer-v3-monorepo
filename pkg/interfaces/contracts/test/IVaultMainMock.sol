// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../vault/VaultTypes.sol";
import { IRateProvider } from "../vault/IRateProvider.sol";

interface IVaultMainMock {
    function getPoolFactoryMock() external view returns (address);

    function burnERC20(address token, address from, uint256 amount) external;

    function mintERC20(address token, address to, uint256 amount) external;

    function setConfig(address pool, PoolConfig calldata config) external;

    function manualRegisterPool(address pool, IERC20[] memory tokens) external;

    function manualRegisterPoolPassThruTokens(address pool, IERC20[] memory tokens) external;

    function manualRegisterPoolAtTimestamp(
        address pool,
        IERC20[] memory tokens,
        uint256 timestamp,
        address pauseManager
    ) external;

    function manualSetLockers(address[] memory lockers) external;

    function manualSetInitializedPool(address pool, bool isPoolInitialized) external;

    function manualSetPoolPaused(address, bool, uint256) external;

    function manualSetVaultState(bool, bool, uint256, uint256) external;

    function manualSetPoolTokenConfig(address, IERC20[] memory, TokenConfig[] memory) external;

    function manualSetPoolConfig(address, PoolConfig memory) external;

    function manualSetPoolTokenBalances(address, IERC20[] memory, uint256[] memory) external;

    function mockWithLocker() external view;

    function mockWithInitializedPool(address pool) external view;

    function mockEnsurePoolNotPaused(address) external view;

    function mockEnsureUnpausedAndGetVaultState(address) external view returns (VaultState memory);

    function mockInternalGetPoolTokenInfo(
        address
    ) external view returns (TokenConfig[] memory, uint256[] memory, uint256[] memory, PoolConfig memory);

    function getDecimalScalingFactors(address pool) external view returns (uint256[] memory);

    function recoveryModeExit(address pool) external view;

    function computePoolDataUpdatingBalancesAndFees(
        address pool,
        Rounding roundingDirection
    ) external returns (PoolData memory);

    function getRawBalances(address pool) external view returns (uint256[] memory balancesRaw);

    function getCurrentLiveBalances(address pool) external view returns (uint256[] memory currentLiveBalances);

    function getLastLiveBalances(address pool) external view returns (uint256[] memory lastLiveBalances);

    function sortTokenConfig(TokenConfig[] memory tokenConfig) external pure returns (TokenConfig[] memory);

    function updateLiveTokenBalanceInPoolData(
        PoolData memory poolData,
        Rounding roundingDirection,
        uint256 tokenIndex
    ) external pure returns (PoolData memory);

    function computeYieldProtocolFeesDue(
        PoolData memory poolData,
        uint256 lastLiveBalance,
        uint256 tokenIndex,
        uint256 yieldFeePercentage
    ) external pure returns (uint256);

    function guardedCheckEntered() external;

    function unguardedCheckNotEntered() external view;

    // Convenience functions for constructing TokenConfig arrays

    function buildTokenConfig(IERC20[] memory tokens) external pure returns (TokenConfig[] memory tokenConfig);

    /// @dev Infers TokenType (STANDARD or WITH_RATE) from the presence or absence of the rate provider.
    function buildTokenConfig(
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders
    ) external pure returns (TokenConfig[] memory tokenConfig);

    /// @dev Infers TokenType (STANDARD or WITH_RATE) from the presence or absence of the rate provider.
    function buildTokenConfig(
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders,
        bool[] memory yieldExemptFlags
    ) external pure returns (TokenConfig[] memory tokenConfig);

    function buildTokenConfig(
        IERC20[] memory tokens,
        TokenType[] memory tokenTypes,
        IRateProvider[] memory rateProviders,
        bool[] memory yieldExemptFlags
    ) external pure returns (TokenConfig[] memory tokenConfig);
}
