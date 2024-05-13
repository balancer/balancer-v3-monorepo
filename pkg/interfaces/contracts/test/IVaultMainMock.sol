// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../vault/VaultTypes.sol";
import { IRateProvider } from "../vault/IRateProvider.sol";
import { IBasePool } from "../vault/IBasePool.sol";

interface IVaultMainMock {
    function getPoolFactoryMock() external view returns (address);

    function burnERC20(address token, address from, uint256 amount) external;

    function mintERC20(address token, address to, uint256 amount) external;

    function setConfig(address pool, PoolConfig calldata config) external;

    function manualRegisterPool(address pool, IERC20[] memory tokens) external;

    function manualRegisterPoolWithSwapFee(address pool, IERC20[] memory tokens, uint256 swapFeePercentage) external;

    function manualRegisterPoolPassThruTokens(address pool, IERC20[] memory tokens) external;

    function manualRegisterPoolAtTimestamp(
        address pool,
        IERC20[] memory tokens,
        uint256 timestamp,
        PoolRoleAccounts memory roleAccounts
    ) external;

    function manualSetIsUnlocked(bool status) external;

    function manualSetInitializedPool(address pool, bool isPoolInitialized) external;

    function manualSetPoolPaused(address, bool) external;

    function manualSetPoolPauseWindowEndTime(address, uint256) external;

    function manualSetVaultPaused(bool) external;

    function manualSetVaultState(bool, bool, uint256, uint256) external;

    function manualSetPoolTokenConfig(address, IERC20[] memory, TokenConfig[] memory) external;

    function manualSetPoolConfig(address, PoolConfig memory) external;

    function manualSetPoolTokenBalances(address, IERC20[] memory, uint256[] memory) external;

    function mockIsUnlocked() external view;

    function mockWithInitializedPool(address pool) external view;

    function ensurePoolNotPaused(address) external view;

    function ensureUnpausedAndGetVaultState(address) external view returns (VaultState memory);

    function internalGetPoolTokenInfo(
        address
    ) external view returns (TokenConfig[] memory, uint256[] memory, uint256[] memory, PoolConfig memory);

    function internalGetBufferUnderlyingSurplus(IERC4626 wrappedToken) external view returns (uint256);

    function internalGetBufferWrappedSurplus(IERC4626 wrappedToken) external view returns (uint256);

    function getDecimalScalingFactors(address pool) external view returns (uint256[] memory);

    function getMaxConvertError() external view returns (uint256);

    function recoveryModeExit(address pool) external view;

    function computePoolDataUpdatingBalancesAndFees(
        address pool,
        Rounding roundingDirection
    ) external returns (PoolData memory);

    function getRawBalances(address pool) external view returns (uint256[] memory balancesRaw);

    function getCurrentLiveBalances(address pool) external view returns (uint256[] memory currentLiveBalances);

    function getLastLiveBalances(address pool) external view returns (uint256[] memory lastLiveBalances);

    function updateLiveTokenBalanceInPoolData(
        PoolData memory poolData,
        uint256 newRawBalance,
        Rounding roundingDirection,
        uint256 tokenIndex
    ) external pure returns (PoolData memory);

    function computeYieldFeesDue(
        PoolData memory poolData,
        uint256 lastLiveBalance,
        uint256 tokenIndex,
        uint256 protocolYieldFeePercentage
    ) external pure returns (uint256, uint256);

    function guardedCheckEntered() external;

    function unguardedCheckNotEntered() external view;

    // Convenience functions for constructing TokenConfig arrays

    function buildTokenConfig(IERC20[] memory tokens) external view returns (TokenConfig[] memory tokenConfig);

    /// @dev Infers TokenType (STANDARD or WITH_RATE) from the presence or absence of the rate provider.
    function buildTokenConfig(
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders
    ) external view returns (TokenConfig[] memory tokenConfig);

    /// @dev Infers TokenType (STANDARD or WITH_RATE) from the presence or absence of the rate provider.
    function buildTokenConfig(
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders,
        bool[] memory yieldFeeFlags
    ) external view returns (TokenConfig[] memory tokenConfig);

    function buildTokenConfig(
        IERC20[] memory tokens,
        TokenType[] memory tokenTypes,
        IRateProvider[] memory rateProviders,
        bool[] memory yieldFeeFlags
    ) external view returns (TokenConfig[] memory tokenConfig);

    function accountDelta(IERC20 token, int256 delta) external;

    function supplyCredit(IERC20 token, uint256 credit) external;

    function takeDebt(IERC20 token, uint256 debt) external;

    function manualSetAccountDelta(IERC20 token, int256 delta) external;

    function manualSetNonZeroDeltaCount(uint256 deltaCount) external;

    function manualInternalSwap(
        SwapParams memory params,
        SwapVars memory vars,
        PoolData memory poolData,
        VaultState memory vaultState
    )
        external
        returns (
            uint256 amountCalculated,
            uint256 amountIn,
            uint256 amountOut,
            SwapParams memory,
            SwapVars memory,
            PoolData memory,
            VaultState memory
        );

    function manualSetPoolCreatorFees(address pool, IERC20 token, uint256 value) external;

    function manualBuildPoolSwapParams(
        SwapParams memory params,
        SwapVars memory vars,
        PoolData memory poolData
    ) external view returns (IBasePool.PoolSwapParams memory);

    function manualComputeAndChargeProtocolAndCreatorFees(
        PoolData memory poolData,
        uint256 swapFeeAmountScaled18,
        uint256 protocolSwapFeePercentage,
        address pool,
        IERC20 token,
        uint256 index
    ) external returns (uint256 protocolSwapFeeAmountRaw, uint256 creatorSwapFeeAmountRaw);

    function manualUpdatePoolDataLiveBalancesAndRates(
        address pool,
        PoolData memory poolData,
        Rounding roundingDirection
    ) external view returns (PoolData memory);

    function manualAddLiquidity(
        PoolData memory poolData,
        AddLiquidityParams memory params,
        uint256[] memory maxAmountsInScaled18,
        VaultState memory vaultState
    )
        external
        returns (
            uint256[] memory amountsInRaw,
            uint256[] memory amountsInScaled18,
            uint256 bptAmountOut,
            bytes memory returnData
        );

    function manualUpdateReservesAfterWrapping(
        IERC20 underlyingToken,
        IERC20 wrappedToken
    ) external returns (uint256, uint256);

    function manualTransfer(IERC20 token, address to, uint256 amount) external;
}
