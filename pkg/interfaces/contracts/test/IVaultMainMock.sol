// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "../solidity-utils/helpers/IRateProvider.sol";
import "../vault/VaultTypes.sol";

interface IVaultMainMock {
    function getPoolFactoryMock() external view returns (address);

    function burnERC20(address token, address from, uint256 amount) external;

    function mintERC20(address token, address to, uint256 amount) external;

    function manualRegisterPool(address pool, IERC20[] memory tokens) external;

    function manualRegisterPoolWithSwapFee(address pool, IERC20[] memory tokens, uint256 swapFeePercentage) external;

    function manualRegisterPoolPassThruTokens(address pool, IERC20[] memory tokens) external;

    function manualRegisterPoolAtTimestamp(
        address pool,
        IERC20[] memory tokens,
        uint32 timestamp,
        PoolRoleAccounts memory roleAccounts
    ) external;

    function manualSetPoolRegistered(address pool, bool status) external;

    function manualSetInitializedPool(address pool, bool isPoolInitialized) external;

    function manualSetPoolPaused(address, bool) external;

    function manualSetPoolPauseWindowEndTime(address, uint32) external;

    function manualSetVaultPaused(bool) external;

    function manualSetVaultState(bool, bool) external;

    function manualSetPoolTokenInfo(address, TokenConfig[] memory) external;

    function manualSetPoolTokenInfo(address, IERC20[] memory, TokenInfo[] memory) external;

    function manualSetPoolConfig(address pool, PoolConfig memory config) external;

    function manualSetHooksConfig(address pool, HooksConfig memory config) external;

    function manualSetStaticSwapFeePercentage(address pool, uint256 value) external;

    /// @dev Does not check the value against any min/max limits normally enforced by the pool.
    function manualUnsafeSetStaticSwapFeePercentage(address pool, uint256 value) external;

    function manualSetPoolTokens(address pool, IERC20[] memory tokens) external;

    function manualSetPoolTokensAndBalances(address, IERC20[] memory, uint256[] memory, uint256[] memory) external;

    function manualSetPoolBalances(address, uint256[] memory, uint256[] memory) external;

    function manualSetPoolConfigBits(address pool, PoolConfigBits config) external;

    function mockIsUnlocked() external view;

    function mockWithInitializedPool(address pool) external view;

    function ensurePoolNotPaused(address) external view;

    function ensureUnpausedAndGetVaultState(address) external view returns (VaultState memory);

    function internalGetBufferUnderlyingImbalance(IERC4626 wrappedToken) external view returns (int256);

    function internalGetBufferWrappedImbalance(IERC4626 wrappedToken) external view returns (int256);

    function getBufferTokenBalancesBytes(IERC4626 wrappedToken) external view returns (bytes32);

    function recoveryModeExit(address pool) external view;

    function loadPoolDataUpdatingBalancesAndYieldFees(
        address pool,
        Rounding roundingDirection
    ) external returns (PoolData memory);

    function loadPoolDataUpdatingBalancesAndYieldFeesReentrancy(
        address pool,
        Rounding roundingDirection
    ) external returns (PoolData memory);

    function manualWritePoolBalancesToStorage(address pool, PoolData memory poolData) external;

    function getRawBalances(address pool) external view returns (uint256[] memory balancesRaw);

    function getLastLiveBalances(address pool) external view returns (uint256[] memory lastBalancesLiveScaled18);

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
        uint256 aggregateYieldFeePercentage
    ) external pure returns (uint256);

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

    function manualSetReservesOf(IERC20 token, uint256 reserves) external;

    function manualInternalSwap(
        VaultSwapParams memory vaultSwapParams,
        SwapState memory state,
        PoolData memory poolData
    )
        external
        returns (
            uint256 amountCalculatedRaw,
            uint256 amountCalculatedScaled18,
            uint256 amountIn,
            uint256 amountOut,
            VaultSwapParams memory,
            SwapState memory,
            PoolData memory
        );

    function manualReentrancySwap(
        VaultSwapParams memory vaultSwapParams,
        SwapState memory state,
        PoolData memory poolData
    ) external;

    function manualGetAggregateSwapFeeAmount(address pool, IERC20 token) external view returns (uint256);

    function manualGetAggregateYieldFeeAmount(address pool, IERC20 token) external view returns (uint256);

    function manualSetAggregateSwapFeeAmount(address pool, IERC20 token, uint256 value) external;

    function manualSetAggregateYieldFeeAmount(address pool, IERC20 token, uint256 value) external;

    function manualSetAggregateSwapFeePercentage(address pool, uint256 value) external;

    function manualSetAggregateYieldFeePercentage(address pool, uint256 value) external;

    function manualBuildPoolSwapParams(
        VaultSwapParams memory vaultSwapParams,
        SwapState memory state,
        PoolData memory poolData
    ) external view returns (PoolSwapParams memory);

    function manualComputeAndChargeAggregateSwapFees(
        PoolData memory poolData,
        uint256 totalSwapFeeAmountScaled18,
        address pool,
        IERC20 token,
        uint256 index
    ) external returns (uint256 totalSwapFeeAmountRaw, uint256 aggregateSwapFeeAmountRaw);

    function manualUpdatePoolDataLiveBalancesAndRates(
        address pool,
        PoolData memory poolData,
        Rounding roundingDirection
    ) external view returns (PoolData memory);

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
        );

    function manualReentrancyAddLiquidity(
        PoolData memory poolData,
        AddLiquidityParams memory params,
        uint256[] memory maxAmountsInScaled18
    ) external;

    function forceUnlock() external;

    function forceLock() external;

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
        );

    function manualReentrancyRemoveLiquidity(
        PoolData memory poolData,
        RemoveLiquidityParams memory params,
        uint256[] memory minAmountsOutScaled18
    ) external;

    function manualSettleWrap(
        IERC20 underlyingToken,
        IERC20 wrappedToken,
        uint256 underlyingHint,
        uint256 wrappedHint
    ) external;

    function manualSettleUnwrap(
        IERC20 underlyingToken,
        IERC20 wrappedToken,
        uint256 underlyingHint,
        uint256 wrappedHint
    ) external;

    function manualTransfer(IERC20 token, address to, uint256 amount) external;

    function manualGetPoolConfigBits(address pool) external view returns (PoolConfigBits);

    function manualErc4626BufferWrapOrUnwrapReentrancy(
        BufferWrapOrUnwrapParams memory params
    ) external returns (uint256 amountCalculatedRaw, uint256 amountInRaw, uint256 amountOutRaw);

    function manualSetBufferAsset(IERC4626 wrappedToken, address underlyingToken) external;

    function manualSetBufferOwnerShares(IERC4626 wrappedToken, address owner, uint256 shares) external;

    function manualSetBufferTotalShares(IERC4626 wrappedToken, uint256 shares) external;

    function manualSetBufferBalances(IERC4626 wrappedToken, uint256 underlyingAmount, uint256 wrappedAmount) external;

    function manualSettleReentrancy(IERC20 token) external returns (uint256 paid);

    function manualSendToReentrancy(IERC20 token, address to, uint256 amount) external;

    function manualFindTokenIndex(IERC20[] memory tokens, IERC20 token) external pure returns (uint256 index);

    function manualSetAddLiquidityCalledFlag(address pool, bool flag) external;

    function manualSetPoolCreator(address pool, address newPoolCreator) external;

    function ensureValidTradeAmount(uint256 tradeAmount) external view;

    function ensureValidSwapAmount(uint256 tradeAmount) external view;

    function manualUpdateAggregateSwapFeePercentage(address pool, uint256 newAggregateSwapFeePercentage) external;

    function manualGetAddLiquidityCalledFlagBySession(address pool, uint256 sessionId) external view returns (bool);

    function manualGetCurrentUnlockSessionId() external view returns (uint256);
}
