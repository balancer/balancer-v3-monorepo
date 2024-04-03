// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IBufferPool } from "@balancer-labs/v3-interfaces/contracts/vault/IBufferPool.sol";
import {
    AddLiquidityKind,
    RemoveLiquidityKind,
    SwapParams,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { BasePoolAuthentication } from "./BasePoolAuthentication.sol";
import { BalancerPoolToken } from "./BalancerPoolToken.sol";
import { BasePoolHooks } from "./BasePoolHooks.sol";

interface VaultV2 {
    function wrapERC4626(IERC4626 wrappedToken, uint256 wrappedAmount) external returns (uint256 paid);
    function unwrapERC4626(IERC4626 wrappedToken, uint256 wrappedAmount) external returns (uint256 paid);

}

/// @notice ERC4626 Buffer Pool, designed to be used to facilitate swaps with ERC4626 tokens in standard pools.
contract ERC4626BufferPool is
    IBasePool,
    IBufferPool,
    IRateProvider,
    BalancerPoolToken,
    BasePoolHooks,
    BasePoolAuthentication,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    uint256 internal immutable _wrappedTokenIndex;
    uint256 internal immutable _baseTokenIndex;

    // Due to rounding issues, the swap operation in a rebalance can miscalculate token amounts by 1 or 2.
    // When the swap is settled, these extra tokens are either added to the pool balance or are left behind
    // in the buffer contract as dust, to fund subsequent operations.
    uint256 public constant DUST_BUFFER = 2;
    uint256 public constant FIFTY_PERCENT = 5e17;

    IERC4626 internal immutable _wrappedToken;
    uint256 internal immutable _wrappedTokenScalingFactor;
    uint256 internal immutable _baseTokenScalingFactor;

    // If we trigger a rebalance from the `onBeforeSwap` hook, the internal swap on the pool will call this hook again.
    // Use this flag as an internal reentrancy guard to avoid recursion.
    // TODO: Should be transient.
    bool private _inSwapContext;

    // Apply to edge-case handling functions so that we don't need to remember to set/clear the context flag.
    modifier performsInternalSwap() {
        _inSwapContext = true;
        _;
        _inSwapContext = false;
    }

    // Uses the factory as the Authentication disambiguator.
    constructor(
        string memory name,
        string memory symbol,
        IERC4626 wrappedToken,
        IVault vault
    ) BalancerPoolToken(vault, name, symbol) BasePoolAuthentication(vault, msg.sender) {
        address baseToken = wrappedToken.asset();

        _wrappedToken = wrappedToken;
        _wrappedTokenScalingFactor = ScalingHelpers.computeScalingFactor(IERC20(address(wrappedToken)));
        _baseTokenScalingFactor = ScalingHelpers.computeScalingFactor(IERC20(baseToken));

        _wrappedTokenIndex = address(wrappedToken) > baseToken ? 1 : 0;
        _baseTokenIndex = address(wrappedToken) > baseToken ? 0 : 1;
    }

    /// @inheritdoc IBasePool
    function getPoolTokens() public view onlyVault returns (IERC20[] memory tokens) {
        return getVault().getPoolTokens(address(this));
    }

    /// @inheritdoc IBufferPool
    function getWrappedTokenIndex() external view returns (uint256) {
        return _wrappedTokenIndex;
    }

    /// @inheritdoc IBufferPool
    function getBaseTokenIndex() external view returns (uint256) {
        return _baseTokenIndex;
    }

    /// @inheritdoc BasePoolHooks
    function onBeforeInitialize(
        uint256[] memory exactAmountsInScaled18,
        bytes memory
    ) external view override onlyVault returns (bool) {
        return exactAmountsInScaled18.length == 2 && _isBufferPoolBalanced(exactAmountsInScaled18);
    }

    /// @inheritdoc BasePoolHooks
    function onBeforeAddLiquidity(
        address,
        AddLiquidityKind kind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external view override onlyVault returns (bool) {
        return kind == AddLiquidityKind.PROPORTIONAL;
    }

    /// @inheritdoc BasePoolHooks
    function onBeforeRemoveLiquidity(
        address,
        RemoveLiquidityKind kind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external view override onlyVault returns (bool) {
        // Only support proportional remove liquidity.
        return kind == RemoveLiquidityKind.PROPORTIONAL;
    }

    /// @inheritdoc BasePoolHooks
    function onBeforeSwap(IBasePool.PoolSwapParams calldata params) external override onlyVault returns (bool) {
        // Ensure we have enough liquidity to accommodate the trade. Since these pools use Linear Math in the swap
        // context, we can use amountGiven as the trade amount, and assume amountCalculated = amountGiven.

        // If the trade amount is greater than the available balance, the buffer swap would fail without intervention.
        // Since it's Linear Math, the "available balance" is the amount of tokenOut, regardless of whether the trade
        // is ExactIn or ExactOut.
        if (params.amountGivenScaled18 > params.balancesScaled18[params.indexOut]) {
            uint256 totalBufferLiquidityScaled18 = params.balancesScaled18[0] + params.balancesScaled18[1];

            // If there is not enough total liquidity in the buffer to support the trade, we can't use the buffer.
            if (params.amountGivenScaled18 > totalBufferLiquidityScaled18) {
                // TODO: Should be handled somehow at the pool level (e.g., pool detects buffer failure and
                //  wraps/unwraps by itself).
                return false;
            } else {
                // The buffer pool is currently too unbalanced to allow the trade, so we need to "counter swap" to fix
                // this and allow the trade to proceed.
                _handleUnbalancedPoolSwaps(params, totalBufferLiquidityScaled18);
            }
        }

        return true;
    }

    function _handleUnbalancedPoolSwaps(
        IBasePool.PoolSwapParams calldata params,
        uint256 totalBufferLiquidityScaled18
    ) private performsInternalSwap {
        // If the trade amount is less than half the total liquidity, the built-in 50/50 rebalance will allow
        // the trade to succeed.
        if (params.amountGivenScaled18 <= totalBufferLiquidityScaled18 / 2) {
            _rebalance(FIFTY_PERCENT);
        } else {
            // The trade amount is greater than half the liquidity - but less than all of it - so we
            // need to do a more precise "counter swap" to enable the trade to succeed.
            uint256 desiredBaseTokenPercentage;

            if (
                (params.kind == SwapKind.EXACT_IN && params.indexIn == _baseTokenIndex) ||
                (params.kind == SwapKind.EXACT_OUT && params.indexOut == _wrappedTokenIndex)
            ) {
                // amountGivenScaled18 is the amount of wrapped out, so we need to calculate the proportion of
                // base tokens which is: baseAmount = liquidity - wrappedAmount
                desiredBaseTokenPercentage = (totalBufferLiquidityScaled18 - params.amountGivenScaled18).divDown(
                    totalBufferLiquidityScaled18
                );

                // Swapping base to wrapped. We need to unbalance the pool to the wrapped side, to make sure we
                // have enough tokens to trade (desired base percentage - 1)
                if (desiredBaseTokenPercentage >= 1) {
                    desiredBaseTokenPercentage -= 1;
                } else {
                    desiredBaseTokenPercentage = 0;
                }
            } else {
                // amountGivenScaled18 is the amount of base out, so we can calculate the percentage directly
                desiredBaseTokenPercentage = params.amountGivenScaled18.divDown(totalBufferLiquidityScaled18);

                // Swapping wrapped to base. We need to unbalance the pool to the base side, to make sure we
                // have enough tokens to trade (desired base percentage + 1)
                desiredBaseTokenPercentage += 1;
                if (desiredBaseTokenPercentage > FixedPoint.ONE) {
                    desiredBaseTokenPercentage = FixedPoint.ONE;
                }
            }

            _rebalance(desiredBaseTokenPercentage);
        }
    }

    /// @inheritdoc IBasePool
    function onSwap(IBasePool.PoolSwapParams memory request) public view onlyVault returns (uint256) {
        // Use linear math
        return request.amountGivenScaled18;
    }

    /// @inheritdoc IBasePool
    function computeInvariant(uint256[] memory balancesLiveScaled18) public view onlyVault returns (uint256) {
        return balancesLiveScaled18[0] + balancesLiveScaled18[1];
    }

    /// @inheritdoc IRateProvider
    function getRate() external view onlyVault returns (uint256) {
        return _getRate();
    }

    /// @inheritdoc IBufferPool
    function rebalance() external authenticate {
        _rebalance(FIFTY_PERCENT);
    }

    /// @dev Non-reentrant to ensure we don't try to externally rebalance during an internal rebalance.
    function _rebalance(uint256 percentageBase) internal nonReentrant {
        address poolAddress = address(this);
        IVault vault = getVault();

        // Get balance of tokens
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, uint256[] memory decimalScalingFactors, ) = vault
            .getPoolTokenInfo(poolAddress);

        // PreviewRedeem converts a wrapped amount into a base amount
        uint256 balanceWrappedAssetsRaw = _wrappedToken.previewRedeem(balancesRaw[_wrappedTokenIndex]);
        uint256 balanceBaseAssetsRaw = balancesRaw[_baseTokenIndex];

        uint256[] memory balancesScaled18 = new uint256[](2);
        // "toScaled18RoundDown" is a "mulDown", and since the balance is divided by FixedPoint.ONE,
        // solidity always rounds down.
        balancesScaled18[_wrappedTokenIndex] = balanceWrappedAssetsRaw.toScaled18RoundDown(
            decimalScalingFactors[_wrappedTokenIndex]
        );
        balancesScaled18[_baseTokenIndex] = balanceBaseAssetsRaw.toScaled18RoundDown(
            decimalScalingFactors[_baseTokenIndex]
        );

        if (percentageBase == FIFTY_PERCENT && _isBufferPoolBalanced(balancesScaled18)) {
            return;
        }

        uint256 exchangeAmountRaw;
        uint256 totalLiquidityRaw = balanceWrappedAssetsRaw + balanceBaseAssetsRaw;
        uint256 desiredBaseAssetsRaw = totalLiquidityRaw.mulDown(percentageBase);
        if (balanceBaseAssetsRaw < desiredBaseAssetsRaw) {
            unchecked {
                exchangeAmountRaw = desiredBaseAssetsRaw - balanceBaseAssetsRaw;
            }
            VaultV2(address(vault)).unwrapERC4626(IERC4626(address(tokens[_wrappedTokenIndex])), exchangeAmountRaw);
        } else {
            unchecked {
                exchangeAmountRaw = balanceBaseAssetsRaw - desiredBaseAssetsRaw;
            }
            VaultV2(address(vault)).wrapERC4626(IERC4626(address(tokens[_wrappedTokenIndex])), exchangeAmountRaw);
        }
    }

    function _isBufferPoolBalanced(uint256[] memory balancesScaled18) private view returns (bool) {
        if (balancesScaled18[0] == balancesScaled18[1]) {
            return true;
        }

        // If not perfectly proportional, makes sure that the difference is within tolerance.
        // The tolerance depends on the decimals of the token, because it introduces imprecision to the rate
        // calculation, and on the initial balance of the pool (since balancesScaled18 has 18 decimals,
        // it's divided by FixedPoint.ONE [mulDown] so we get only the integer part of the number)
        uint256 wrappedTokenIdx = _wrappedTokenIndex;
        uint256 baseTokenIdx = _baseTokenIndex;
        uint256 tolerance;

        if (balancesScaled18[wrappedTokenIdx] >= balancesScaled18[baseTokenIdx]) {
            // E.g. let's assume that the wrapped balance is 1000 wUSDC, with 6 decimals, and the rate is
            // FixedPoint.ONE
            // There are 2 sources of imprecision:
            //    1. Vault scales to 18, but token has only 6 decimals. The remaining 12 are imprecise
            //    2. Since we have 1000 wUSDC, the scaled18 balance is approx 1e21, but the vault rate has
            //       only 18 decimals. The 3 extra digits are imprecise.
            // The whole imprecision is 15 digits, so the tolerance should be 1e15.
            // Doing the example math below:
            // - balancesScaled18[wrappedTokenIdx] = convertToAssets(1000) * 1e12 ~= (1e3 * 1e6) * 1e12 = 1e21
            // - _wrappedTokenScalingFactor = 1e(18-6) * 1e18 = 1e30
            // - balancesScaled18[wrappedTokenIdx].mulDown(_wrappedTokenScalingFactor) = 1e21 * 1e30 / 1e18 = 1e33
            // - tolerance = 1e33 / 1e18 = 1e15
            // i.e. 1000 wUSDC is 1e21, so we are saying that we can only rely in the 6 most meaningful digits.

            tolerance = balancesScaled18[wrappedTokenIdx].mulDown(_wrappedTokenScalingFactor) / FixedPoint.ONE;
            tolerance = tolerance < 1 ? 1 : tolerance;
            return balancesScaled18[wrappedTokenIdx] - balancesScaled18[baseTokenIdx] < tolerance;
        } else {
            tolerance = balancesScaled18[baseTokenIdx].mulDown(_baseTokenScalingFactor) / FixedPoint.ONE;
            tolerance = tolerance < 1 ? 1 : tolerance;
            return balancesScaled18[baseTokenIdx] - balancesScaled18[wrappedTokenIdx] < tolerance;
        }
    }

    function _getRate() private view returns (uint256) {
        // TODO: This is really just a placeholder for now. We will need to think more carefully about this.
        // e.g., it will probably need to be scaled according to the asset value decimals. There may be
        // special cases with 0 supply. Wrappers may implement this differently, so maybe we need to calculate
        // the rate directly instead of relying on the wrapper implementation, etc.
        return _wrappedToken.convertToAssets(FixedPoint.ONE);
    }

    // Unsupported functions that unconditionally revert

    /// @inheritdoc IBasePool
    function computeBalance(
        uint256[] memory, // balancesLiveScaled18,
        uint256, // tokenInIndex,
        uint256 // invariantRatio
    ) external pure returns (uint256) {
        // This pool doesn't support single token add/remove liquidity, so this function is not needed.
        // Should never get here, but need to implement the interface.
        revert IVaultErrors.OperationNotSupported();
    }
}
