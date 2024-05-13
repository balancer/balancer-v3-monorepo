// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { IMinimumSwapFee } from "@balancer-labs/v3-interfaces/contracts/vault/IMinimumSwapFee.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { StorageSlot } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlot.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

import { VaultStateBits, VaultStateLib } from "./lib/VaultStateLib.sol";
import { PoolConfigBits, PoolConfigLib } from "./lib/PoolConfigLib.sol";
import { VaultStorage } from "./VaultStorage.sol";
import { ERC20MultiToken } from "./token/ERC20MultiToken.sol";
import { PackedTokenBalance } from "./lib/PackedTokenBalance.sol";

/**
 * @dev Storage layout for Vault. This contract has no code except for common utilities in the inheritance chain
 * that require storage to work and will be required in both the main Vault and its extension.
 */
abstract contract VaultCommon is IVaultEvents, IVaultErrors, VaultStorage, ReentrancyGuardTransient, ERC20MultiToken {
    using EnumerableMap for EnumerableMap.IERC20ToBytes32Map;
    using PackedTokenBalance for bytes32;
    using PoolConfigLib for PoolConfig;
    using ScalingHelpers for *;
    using SafeCast for *;
    using FixedPoint for *;
    using VaultStateLib for VaultStateBits;
    using TransientStorageHelpers for *;
    using StorageSlot for *;

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /**
     * @dev This modifier ensures that the function it modifies can only be called
     * when a tab has been opened.
     */
    modifier onlyWhenUnlocked() {
        _ensureUnlocked();
        _;
    }

    function _ensureUnlocked() internal view {
        if (_isUnlocked().tload() == false) {
            revert VaultIsNotUnlocked();
        }
    }

    /**
     * @notice Expose the state of the Vault's reentrancy guard.
     * @return True if the Vault is currently executing a nonReentrant function
     */
    function reentrancyGuardEntered() public view returns (bool) {
        return _reentrancyGuardEntered();
    }

    /**
     * @notice Records the `credit` for a given token.
     * @param token   The ERC20 token for which the 'credit' will be accounted.
     * @param credit  The amount of `token` supplied to the Vault in favor of the caller.
     */
    function _supplyCredit(IERC20 token, uint256 credit) internal {
        _accountDelta(token, -credit.toInt256());
    }

    /**
     * @notice Records the `debt` for a given token.
     * @param token   The ERC20 token for which the `debt` will be accounted.
     * @param debt    The amount of `token` taken from the Vault in favor of the caller.
     */
    function _takeDebt(IERC20 token, uint256 debt) internal {
        _accountDelta(token, debt.toInt256());
    }

    /**
     * @dev Accounts the delta for the given token.
     * Positive delta represents debt, while negative delta represents surplus.
     *
     * @param token   The ERC20 token for which the delta is being accounted.
     * @param delta   The difference in the token balance.
     *                Positive indicates a debit or a decrease in Vault's tokens,
     *                negative indicates a credit or an increase in Vault's tokens.
     */
    function _accountDelta(IERC20 token, int256 delta) internal {
        // If the delta is zero, there's nothing to account for.
        if (delta == 0) return;

        // Get the current recorded delta for this token.
        int256 current = _tokenDeltas().tGet(token);

        // Calculate the new delta after accounting for the change.
        int256 next = current + delta;

        unchecked {
            // If the resultant delta becomes zero after this operation,
            // decrease the count of non-zero deltas.
            if (next == 0) {
                _nonzeroDeltaCount().tDecrement();
            }
            // If there was no previous delta (i.e., it was zero) and now we have one,
            // increase the count of non-zero deltas.
            else if (current == 0) {
                _nonzeroDeltaCount().tIncrement();
            }
        }

        // Update the delta for this token.
        _tokenDeltas().tSet(token, next);
    }

    /*******************************************************************************
                                    Vault Pausing
    *******************************************************************************/

    /// @dev Modifier to make a function callable only when the Vault is not paused.
    modifier whenVaultNotPaused() {
        _ensureVaultNotPaused();
        _;
    }

    /// @dev Reverts if the Vault is paused.
    function _ensureVaultNotPaused() internal view {
        if (_isVaultPaused()) {
            revert VaultPaused();
        }
    }

    /**
     * @dev To save some gas, vault state variables are stored in a single word and are read only once.
     * So, it's not possible to use the modifier whenPoolNotPaused , because it requires to read _vaultState
     * one more time. This function optimizes the check if vault and pool are paused and returns the vaultState
     * struct to be used elsewhere
     */
    function _ensureUnpausedAndGetVaultState(address pool) internal view returns (VaultState memory vaultState) {
        vaultState = _vaultState.toVaultState();
        // Check vault and pool paused inline, instead of using modifier, to save some gas reading the
        // isVaultPaused state again in `_isVaultPaused`.
        // solhint-disable-next-line not-rely-on-time
        if (vaultState.isVaultPaused && block.timestamp <= _vaultBufferPeriodEndTime) {
            revert VaultPaused();
        }
        _ensurePoolNotPaused(pool);
    }

    /**
     * @dev For gas efficiency, storage is only read before `_vaultBufferPeriodEndTime`. Once we're past that
     * timestamp, the expression short-circuits false, and the Vault is permanently unpaused.
     */
    function _isVaultPaused() internal view returns (bool) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp <= _vaultBufferPeriodEndTime && _vaultState.isVaultPaused();
    }

    /*******************************************************************************
                                     Pool Pausing
    *******************************************************************************/

    /**
     * @dev Reverts if the pool is paused.
     * @param pool The pool
     */
    function _ensurePoolNotPaused(address pool) internal view {
        if (_isPoolPaused(pool)) {
            revert PoolPaused(pool);
        }
    }

    /// @dev Check both the flag and timestamp to determine whether the pool is paused.
    function _isPoolPaused(address pool) internal view returns (bool) {
        (bool paused, ) = _getPoolPausedState(pool);

        return paused;
    }

    /// @dev Lowest level routine that plucks only the minimum necessary parts from storage.
    function _getPoolPausedState(address pool) internal view returns (bool, uint256) {
        (bool pauseBit, uint256 pauseWindowEndTime) = PoolConfigLib.getPoolPausedState(_poolConfig[pool]);

        // Use the Vault's buffer period.
        // solhint-disable-next-line not-rely-on-time
        return (pauseBit && block.timestamp <= pauseWindowEndTime + _vaultBufferPeriodDuration, pauseWindowEndTime);
    }

    /*******************************************************************************
                                     Buffer Pausing
    *******************************************************************************/
    /// @dev Modifier to make a function callable only when vault buffers are not paused.
    modifier whenVaultBuffersAreNotPaused() {
        _ensureVaultBuffersAreNotPaused();
        _;
    }

    /// @dev Reverts if vault buffers are paused.
    function _ensureVaultBuffersAreNotPaused() internal view {
        if (_vaultState.areBuffersPaused()) {
            revert VaultBuffersArePaused();
        }
    }

    /*******************************************************************************
                            Pool Registration and Initialization
    *******************************************************************************/

    /// @dev Reverts unless `pool` corresponds to a registered Pool.
    modifier withRegisteredPool(address pool) {
        _ensureRegisteredPool(pool);
        _;
    }

    /// @dev Reverts unless `pool` corresponds to an intialized Pool.
    modifier withInitializedPool(address pool) {
        _ensureInitializedPool(pool);
        _;
    }

    /// @dev Reverts unless `pool` corresponds to a registered Pool.
    function _ensureRegisteredPool(address pool) internal view {
        if (!_isPoolRegistered(pool)) {
            revert PoolNotRegistered(pool);
        }
    }

    /// @dev See `isPoolRegistered`
    function _isPoolRegistered(address pool) internal view returns (bool) {
        return _poolConfig[pool].isPoolRegistered();
    }

    /// @dev Reverts unless `pool` corresponds to an initialized Pool.
    function _ensureInitializedPool(address pool) internal view {
        if (!_isPoolInitialized(pool)) {
            revert PoolNotInitialized(pool);
        }
    }

    /// @dev See `isPoolInitialized`
    function _isPoolInitialized(address pool) internal view returns (bool) {
        return _poolConfig[pool].isPoolInitialized();
    }

    /*******************************************************************************
                                    Pool Information
    *******************************************************************************/

    /**
     * @dev Packs and sets the raw and live balances of a Pool's tokens to the current values in poolData.balancesRaw
     * and poolData.liveBalances in the same storage slot.
     */
    function _setPoolBalances(address pool, PoolData memory poolData) internal {
        EnumerableMap.IERC20ToBytes32Map storage poolBalances = _poolTokenBalances[pool];

        for (uint256 i = 0; i < poolData.balancesRaw.length; ++i) {
            // Since we assume all newBalances are properly ordered, we can simply use `unchecked_setAt`
            // to avoid one less storage read per token.
            poolBalances.unchecked_setAt(
                i,
                PackedTokenBalance.toPackedBalance(poolData.balancesRaw[i], poolData.balancesLiveScaled18[i])
            );
        }
    }

    /**
     * @notice Fetches the tokens and their corresponding balances for a given pool.
     * @dev Utilizes an enumerable map to obtain pool token balances.
     * The function is structured to minimize storage reads by leveraging the `unchecked_at` method.
     *
     * @param pool The address of the pool for which tokens and balances are to be fetched.
     * @return tokens An array of token addresses.
     */
    function _getPoolTokens(address pool) internal view returns (IERC20[] memory tokens) {
        // Retrieve the mapping of tokens and their balances for the specified pool.
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances = _poolTokenBalances[pool];

        // Initialize arrays to store tokens based on the number of tokens in the pool.
        tokens = new IERC20[](poolTokenBalances.length());

        for (uint256 i = 0; i < tokens.length; ++i) {
            // Because the iteration is bounded by `tokens.length`, which matches the EnumerableMap's length,
            // we can safely use `unchecked_at`. This ensures that `i` is a valid token index and minimizes
            // storage reads.
            (tokens[i], ) = poolTokenBalances.unchecked_at(i);
        }
    }

    function _getPoolData(address pool, Rounding roundingDirection) internal view returns (PoolData memory poolData) {
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances = _poolTokenBalances[pool];
        mapping(IERC20 => TokenConfig) storage poolTokenConfig = _poolTokenConfig[pool];

        uint256 numTokens = poolTokenBalances.length();
        poolData.poolConfig = _poolConfig[pool].toPoolConfig();

        poolData.tokenConfig = new TokenConfig[](numTokens);
        poolData.balancesRaw = new uint256[](numTokens);
        poolData.balancesLiveScaled18 = new uint256[](numTokens);
        poolData.decimalScalingFactors = PoolConfigLib.getDecimalScalingFactors(poolData.poolConfig, numTokens);
        poolData.tokenRates = new uint256[](numTokens);
        bytes32 packedBalance;
        IERC20 token;

        for (uint256 i = 0; i < numTokens; ++i) {
            (token, packedBalance) = poolTokenBalances.unchecked_at(i);
            poolData.tokenConfig[i] = poolTokenConfig[token];
            _updateTokenRate(poolData, i);
            _updateRawAndLiveTokenBalancesInPoolData(poolData, packedBalance.getBalanceRaw(), roundingDirection, i);
        }
    }

    /**
     * @dev Preconditions: tokenConfig must be current in `poolData`. Side effects: mutates tokenRates in `poolData`.
     */
    function _updateTokenRatesInPoolData(PoolData memory poolData) internal view {
        uint256 numTokens = poolData.tokenConfig.length;

        // Initialize arrays to store tokens based on the number of tokens in the pool.
        poolData.tokenRates = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            _updateTokenRate(poolData, i);
        }
    }

    function _updateTokenRate(PoolData memory poolData, uint256 index) internal view {
        TokenType tokenType = poolData.tokenConfig[index].tokenType;

        if (tokenType == TokenType.STANDARD) {
            poolData.tokenRates[index] = FixedPoint.ONE;
        } else if (tokenType == TokenType.WITH_RATE) {
            poolData.tokenRates[index] = poolData.tokenConfig[index].rateProvider.getRate();
        } else {
            revert InvalidTokenConfiguration();
        }
    }

    /**
     * @dev Get poolData and compute protocol yield fees due, without changing any state.
     * Returns poolData with both raw and live balances updated to reflect the fees.
     */
    function _getPoolDataAndYieldFees(
        address pool,
        Rounding roundingDirection,
        uint256 yieldFeePercentage
    )
        internal
        view
        returns (PoolData memory poolData, uint256[] memory dueProtocolYieldFees, uint256[] memory dueCreatorYieldFees)
    {
        // Initialize poolData with base information for subsequent calculations.
        poolData = _getPoolData(pool, roundingDirection);

        EnumerableMap.IERC20ToBytes32Map storage poolBalances = _poolTokenBalances[pool];
        uint256 numTokens = poolBalances.length();

        dueProtocolYieldFees = new uint256[](numTokens);
        dueCreatorYieldFees = new uint256[](numTokens);

        bool poolSubjectToYieldFees = poolData.poolConfig.isPoolInitialized &&
            yieldFeePercentage > 0 &&
            poolData.poolConfig.isPoolInRecoveryMode == false;

        for (uint256 i = 0; i < numTokens; ++i) {
            TokenConfig memory tokenConfig = poolData.tokenConfig[i];

            // poolData already has live balances computed from raw balances according to the token rates and the
            // given rounding direction. Charging a yield fee changes the raw
            // balance, in which case the safest and most numerically precise way to adjust
            // the live balance is to simply repeat the scaling (hence the second call below).

            // The Vault actually guarantees a token with paysYieldFees set is a WITH_RATE token, so technically we
            // could just check the flag, but we don't want to introduce that dependency for a slight gas savings.
            bool tokenSubjectToYieldFees = tokenConfig.paysYieldFees && tokenConfig.tokenType == TokenType.WITH_RATE;

            // Do not charge yield fees until the pool is initialized, and is not in recovery mode.
            if (poolSubjectToYieldFees && tokenSubjectToYieldFees) {
                (uint256 protocolYieldFeeAmountRaw, uint256 creatorYieldFeeAmountRaw) = _computeYieldFeesDue(
                    poolData,
                    poolBalances.unchecked_valueAt(i).getBalanceDerived(),
                    i,
                    yieldFeePercentage
                );

                if (protocolYieldFeeAmountRaw > 0 || creatorYieldFeeAmountRaw > 0) {
                    dueProtocolYieldFees[i] = protocolYieldFeeAmountRaw;
                    dueCreatorYieldFees[i] = creatorYieldFeeAmountRaw;

                    // Adjust raw and live balances.
                    _updateRawAndLiveTokenBalancesInPoolData(
                        poolData,
                        poolData.balancesRaw[i] - protocolYieldFeeAmountRaw - creatorYieldFeeAmountRaw,
                        roundingDirection,
                        i
                    );
                }
            }
        }
    }

    /**
     * @dev Fill in PoolData, including paying protocol yield fees and computing final raw and live balances.
     * This function modifies protocol fees and balance storage. Since it modifies storage and makes external
     * calls, it must be nonReentrant.
     */
    function _computePoolDataUpdatingBalancesAndFees(
        address pool,
        Rounding roundingDirection,
        uint256 yieldFeePercentage
    ) internal nonReentrant returns (PoolData memory poolData) {
        uint256[] memory dueProtocolYieldFees;
        uint256[] memory dueCreatorYieldFees;

        (poolData, dueProtocolYieldFees, dueCreatorYieldFees) = _getPoolDataAndYieldFees(
            pool,
            roundingDirection,
            yieldFeePercentage
        );
        uint256 numTokens = dueProtocolYieldFees.length;

        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token = poolData.tokenConfig[i].token;
            uint256 yieldFeeAmountRaw = dueProtocolYieldFees[i];

            if (yieldFeeAmountRaw > 0) {
                // Charge protocol fee.
                _protocolFees[pool][token] += yieldFeeAmountRaw;
                emit ProtocolYieldFeeCharged(pool, address(token), yieldFeeAmountRaw);
            }

            uint256 creatorYieldFeeAmountRaw = dueCreatorYieldFees[i];
            if (creatorYieldFeeAmountRaw > 0) {
                // Charge pool creator fee
                _poolCreatorFees[pool][token] += creatorYieldFeeAmountRaw;
                emit PoolCreatorYieldFeeCharged(pool, address(token), creatorYieldFeeAmountRaw);
            }
        }

        // Update raw and last live pool balances, as computed by `_getPoolDataAndYieldFees`
        _setPoolBalances(pool, poolData);
    }

    function _computeYieldFeesDue(
        PoolData memory poolData,
        uint256 lastLiveBalance,
        uint256 tokenIndex,
        uint256 protocolYieldFeePercentage
    ) internal pure returns (uint256 protocolFeeAmountRaw, uint256 creatorFeeAmountRaw) {
        uint256 currentLiveBalance = poolData.balancesLiveScaled18[tokenIndex];

        // Do not charge fees if rates go down. If the rate were to go up, down, and back up again, protocol fees
        // would be charged multiple times on the "same" yield. For tokens subject to yield fees, this should not
        // happen, or at least be very rare. It can be addressed for known volatile rates by setting the yield fee
        // exempt flag on registration, or compensated off-chain if there is an incident with a normally
        // well-behaved rate provider.
        if (currentLiveBalance > lastLiveBalance) {
            unchecked {
                // Magnitudes checked above, so it's safe to do unchecked math here.
                uint256 liveBalanceDiffScaled18 = currentLiveBalance - lastLiveBalance;
                uint256 liveBalanceDiffRaw = liveBalanceDiffScaled18.toRawUndoRateRoundDown(
                    poolData.decimalScalingFactors[tokenIndex],
                    poolData.tokenRates[tokenIndex]
                );

                // A pool is subject to yield fees if poolSubjectToYieldFees is true, meaning that
                // `protocolYieldFeePercentage > 0`. So, we don't need to check this again in here, saving some gas.
                protocolFeeAmountRaw = liveBalanceDiffRaw.mulUp(protocolYieldFeePercentage);

                if (poolData.poolConfig.poolCreatorFeePercentage > 0) {
                    creatorFeeAmountRaw = (liveBalanceDiffRaw - protocolFeeAmountRaw).mulUp(
                        poolData.poolConfig.poolCreatorFeePercentage
                    );
                }
            }
        }
    }

    /**
     * @dev Updates the raw and live balance of a given token in poolData, scaling the given raw balance by both decimal
     * and token rates, and rounding the result in the given direction. Assumes scaling factors and rates are current
     * in PoolData.
     */
    function _updateRawAndLiveTokenBalancesInPoolData(
        PoolData memory poolData,
        uint256 newRawBalance,
        Rounding roundingDirection,
        uint256 tokenIndex
    ) internal pure {
        poolData.balancesRaw[tokenIndex] = newRawBalance;

        function(uint256, uint256, uint256) internal pure returns (uint256) _upOrDown = roundingDirection ==
            Rounding.ROUND_UP
            ? ScalingHelpers.toScaled18ApplyRateRoundUp
            : ScalingHelpers.toScaled18ApplyRateRoundDown;

        poolData.balancesLiveScaled18[tokenIndex] = _upOrDown(
            newRawBalance,
            poolData.decimalScalingFactors[tokenIndex],
            poolData.tokenRates[tokenIndex]
        );
    }

    function _setStaticSwapFeePercentage(address pool, uint256 swapFeePercentage) internal virtual {
        if (swapFeePercentage > _MAX_SWAP_FEE_PERCENTAGE) {
            revert SwapFeePercentageTooHigh();
        }

        // This cannot be called during pool construction. Pools must be deployed first, then registered.
        if (IERC165(pool).supportsInterface(type(IMinimumSwapFee).interfaceId)) {
            if (swapFeePercentage < IMinimumSwapFee(pool).getMinimumSwapFeePercentage()) {
                revert SwapFeePercentageTooLow();
            }
        }

        PoolConfig memory config = PoolConfigLib.toPoolConfig(_poolConfig[pool]);
        config.staticSwapFeePercentage = swapFeePercentage;
        _poolConfig[pool] = config.fromPoolConfig();

        emit SwapFeePercentageChanged(pool, swapFeePercentage);
    }

    /*******************************************************************************
                                    Recovery Mode
    *******************************************************************************/

    /**
     * @dev Place on functions that may only be called when the associated pool is in recovery mode.
     * @param pool The pool
     */
    modifier onlyInRecoveryMode(address pool) {
        _ensurePoolInRecoveryMode(pool);
        _;
    }

    /**
     * @dev Reverts if the pool is not in recovery mode.
     * @param pool The pool
     */
    function _ensurePoolInRecoveryMode(address pool) internal view {
        if (!_isPoolInRecoveryMode(pool)) {
            revert PoolNotInRecoveryMode(pool);
        }
    }

    /**
     * @notice Checks whether a pool is in recovery mode.
     * @param pool Address of the pool to check
     * @return True if the pool is initialized, false otherwise
     */
    function _isPoolInRecoveryMode(address pool) internal view returns (bool) {
        return _poolConfig[pool].isPoolInRecoveryMode();
    }
}
