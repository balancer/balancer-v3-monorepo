// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

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
    AddLiquidityParams,
    RemoveLiquidityKind,
    RemoveLiquidityParams,
    SwapParams,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { StorageSlot } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlot.sol";

import { BasePoolAuthentication } from "./BasePoolAuthentication.sol";
import { BalancerPoolToken } from "./BalancerPoolToken.sol";
import { BasePoolHooks } from "./BasePoolHooks.sol";

/// @notice ERC4626 Buffer Pool, designed to be used to facilitate swaps with ERC4626 tokens in standard pools.
contract ERC4626BufferPool is
    IBasePool,
    IBufferPool,
    IRateProvider,
    IPoolLiquidity,
    BalancerPoolToken,
    BasePoolHooks,
    BasePoolAuthentication,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;
    using StorageSlot for *;

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
    bool private _afterSwapHookRequired;

    // Apply to edge-case handling functions so that we don't need to remember to set/clear the context flag.
    modifier performsInternalSwap() {
        StorageSlot.BooleanSlotType slot;
        assembly {
            slot := _inSwapContext.slot
        }
        slot.tstore(true);
        _;
        slot.tstore(false);
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
        // Only support custom add liquidity.
        return true;
    }

    /// @inheritdoc IPoolLiquidity
    function onAddLiquidityCustom(
        address,
        uint256[] memory,
        uint256 exactBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory
    )
        external
        view
        onlyVault
        returns (
            uint256[] memory amountsInScaled18,
            uint256 bptAmountOut,
            uint256[] memory swapFeeAmountsScaled18,
            bytes memory returnData
        )
    {
        // This is a proportional join
        bptAmountOut = exactBptAmountOut;
        returnData = "";

        amountsInScaled18 = BasePoolMath.computeProportionalAmountsIn(balancesScaled18, totalSupply(), bptAmountOut);
        swapFeeAmountsScaled18 = new uint256[](balancesScaled18.length);
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
        return true;
    }

    /// @inheritdoc BasePoolHooks
    function onBeforeSwap(IBasePool.PoolSwapParams calldata params) external override onlyVault returns (bool) {
        {
            StorageSlot.BooleanSlotType slot;
            assembly {
                slot := _inSwapContext.slot
            }

            // Short-circuit if we're already inside an `onBeforeSwap` hook.
            if (slot.tload() == true) {
                return true;
            }

        }

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
                IVault vault = getVault();
                uint256[] memory rates = vault.getPoolTokenRates(address(this));
                uint256[] memory amountsIn = new uint256[](2);
                amountsIn[params.indexIn] = params.amountGivenScaled18.divDown(rates[params.indexIn]);
                (, uint256 bptAmountOut,) = vault.addLiquidity(AddLiquidityParams({
                    pool: address(this),
                    to: address(this),
                    maxAmountsIn: amountsIn,
                    minBptAmountOut: 1,
                    kind: AddLiquidityKind.UNBALANCED,
                    userData: ""
                }));

                console.log('##### BPT AMOUNT OUT: ', bptAmountOut);

                totalBufferLiquidityScaled18 += params.amountGivenScaled18;

                _handleUnbalancedPoolSwaps(params, totalBufferLiquidityScaled18);

                StorageSlot.BooleanSlotType slot;
                assembly {
                    slot := _afterSwapHookRequired.slot
                }
                slot.tstore(true);
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
        // If onSwap was triggered by the rebalance function, use the rate (expensive, but more precise)
        // Since the rebalance function is the only one marked non-reentrant, we can use that guard directly.
        // Note that this ReentrancyGuard is local to the pool, not related to the Vault's separate ReentrancyGuard.
        // NB: If this ever changes, we would need to create another modifier on the rebalance function and check that.
        if (_reentrancyGuardEntered()) {
            // Rate used by the vault to scale values
            uint256 wrappedRate = _getRate();

            uint256 sharesRaw = request.amountGivenScaled18.divDown(wrappedRate).divDown(_wrappedTokenScalingFactor);

            uint256 assetsRaw;
            if (request.kind == SwapKind.EXACT_IN) {
                // Adds DUST_BUFFER to the amount of assets to make sure we return fewer wrapped tokens than we
                // obtained from amountIn. Since the buffer will unwrap less than amountIn, this contract
                // must be funded with enough base tokens to make up the difference.
                assetsRaw = _wrappedToken.previewRedeem(sharesRaw) + DUST_BUFFER;
            } else {
                // Subtract DUST_BUFFER-1 (due to rounding direction, we need to remove 1 from DUST_BUFFER)
                // from the amount of assets to make sure we return more wrapped than we obtained from amountOut.
                // Since the buffer will wrap more assets than amountOut, this contract must be funded with enough
                // base tokens to make up the difference.
                assetsRaw = _wrappedToken.previewRedeem(sharesRaw) - DUST_BUFFER + 1;
            }
            uint256 preciseAssetsScaled18 = assetsRaw.mulDown(_wrappedTokenScalingFactor);

            // amountGivenScaled18 has some imprecision when calculating the rate (we store only 18 decimals of rate,
            // therefore it's less precise than using preview or convertToAssets directly).
            // So, we need to return the linear math value (amountGivenScaled18), but add the error introduced by
            // the rate difference, which is calculated by (amountGivenScaled18 - preciseAssetsScaled18), i.e.:
            //
            // amountGivenScaled18 + (error)
            //
            //     where error is (amountGivenScaled18 - preciseAssetsScaled18)
            return 2 * request.amountGivenScaled18 - preciseAssetsScaled18;
        } else {
            // If onSwap wasn't triggered by the rebalance function, use linear math
            return request.amountGivenScaled18;
        }
    }

    function onAfterSwap(AfterSwapParams calldata params, uint256) external virtual override returns (bool) {
        {
            StorageSlot.BooleanSlotType slot;
            assembly {
                slot := _afterSwapHookRequired.slot
            }
            
            if (slot.tload() == false) {
                return true;
            } else {
                slot.tstore(false);
            }
        }
    
        IVault vault = getVault();

        uint256[] memory minAmountsOut = new uint256[](2);
        console.log('tokenIn balance: ', params.tokenInBalanceScaled18);
        console.log('tokenOut balance: ', params.tokenOutBalanceScaled18);
        minAmountsOut[address(params.tokenIn) == address(_wrappedToken) ? _wrappedTokenIndex : _baseTokenIndex] = 1;
        vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: address(this),
                from: address(this),
                maxBptAmountIn: IERC20(this).balanceOf(address(this)),
                minAmountsOut: minAmountsOut,
                kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                userData: params.userData
            })
        );

        return true;
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
        getVault().lock(abi.encodeWithSelector(ERC4626BufferPool.forcedRebalanceHook.selector));
    }

    function forcedRebalanceHook() external payable onlyVault {
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

            _rebalanceInternal(poolAddress, tokens, exchangeAmountRaw, SwapKind.EXACT_IN);
        } else {
            unchecked {
                exchangeAmountRaw = balanceBaseAssetsRaw - desiredBaseAssetsRaw;
            }

            _rebalanceInternal(poolAddress, tokens, exchangeAmountRaw, SwapKind.EXACT_OUT);
        }
    }

    /**
     * @dev Shift the balances in a given direction (on an external rebalance, to the equal value point).
     * ExactIn unwraps wrapped and deposits more base tokens: shifts balance from wrapped to base.
     * ExactOut does the opposite: wraps base tokens and deposits more wrapped: shifts balances from base to wrapped.
     * `exchangeAmountRaw` should be in raw base decimals.
     */
    function _rebalanceInternal(
        address poolAddress,
        IERC20[] memory tokens,
        uint256 exchangeAmountRaw,
        SwapKind kind
    ) private {
        uint256 limitRaw;
        if (kind == SwapKind.EXACT_IN) {
            // Since onSwap will consider a slightly bigger rate for the wrapped token, we need to account that
            // in the minimum limit of amountOut calculation, and that's why (exchangeAmountRaw - 2) is converted.
            // Also, since the unwrap operation has RoundDown divisions, DUST_BUFFER needs to be subtracted
            // from amountOut too
            limitRaw = _wrappedToken.convertToShares(exchangeAmountRaw - DUST_BUFFER) - DUST_BUFFER;

            // In this case, since there is more wrapped than base assets, wrapped tokens will be removed (tokenOut)
            // and then unwrapped, and the resulting base assets will be deposited in the pool (tokenIn).
            rebalanceHook(
                SwapParams({
                    kind: SwapKind.EXACT_IN,
                    pool: poolAddress,
                    tokenIn: tokens[_baseTokenIndex],
                    tokenOut: tokens[_wrappedTokenIndex],
                    amountGivenRaw: exchangeAmountRaw,
                    limitRaw: limitRaw,
                    userData: ""
                })
            );
        } else {
            // Since onSwap will consider a slightly bigger rate for the wrapped token, we need to account that
            // in the maximum limit of amountIn calculation, and that's why (exchangeAmountRaw + 2) is converted.
            // Also, since the wrap operation has RoundDown divisions, DUST_BUFFER needs to be added
            // to amountIn too
            limitRaw = _wrappedToken.convertToShares(exchangeAmountRaw + DUST_BUFFER) + DUST_BUFFER;

            // In this case, since there is more base than wrapped assets, base assets will be removed (tokenOut)
            // and then wrapped, and the resulting wrapped assets will be deposited in the pool (tokenIn).
            rebalanceHook(
                SwapParams({
                    kind: SwapKind.EXACT_OUT,
                    pool: poolAddress,
                    tokenIn: tokens[_wrappedTokenIndex],
                    tokenOut: tokens[_baseTokenIndex],
                    amountGivenRaw: exchangeAmountRaw,
                    limitRaw: limitRaw,
                    userData: ""
                })
            );
        }
    }

    function rebalanceHook(SwapParams memory params) internal {
        IVault vault = getVault();

        (, uint256 amountIn, uint256 amountOut) = _swapHook(params);

        IERC20 baseToken;
        IERC20 wrappedToken;

        if (params.kind == SwapKind.EXACT_IN) {
            baseToken = params.tokenIn;
            wrappedToken = params.tokenOut;

            vault.sendTo(wrappedToken, address(this), amountOut);
            // Using redeem, instead of withdraw, to pass the amount of shares (amountOut) instead of the
            // amount of assets. That's because amount of shares is an output of onSwap, so we make sure
            // the buffer contract will never have a different balance of wrapped tokens after the rebalance
            // occurs
            IERC4626(address(wrappedToken)).redeem(amountOut, address(this), address(this));
            // The explicit transfer is needed, because onSwap considers a slightly larger rate for the wrapped token,
            // so the redeem function returns a bit less assets than amountIn
            baseToken.safeTransfer(address(vault), amountIn);
            vault.settle(baseToken);
        } else {
            baseToken = params.tokenOut;
            wrappedToken = params.tokenIn;
            // Since the rate used by onSwap is a bit larger than the real rate, the mint operation
            // will take more assets than amountOut. So, we need to recalculate the amount of assets
            // taken to approve the exact amount that will be minted
            uint256 preciseAmountOut = IERC4626(address(wrappedToken)).previewMint(amountIn);

            vault.sendTo(baseToken, address(this), amountOut);
            baseToken.approve(address(wrappedToken), preciseAmountOut);
            // Using mint, instead of deposit, to pass the amount of shares (amountIn) instead of the
            // amount of assets. That's because amount of shares is an output of onSwap, so we make sure
            // the buffer contract will never have a different balance of wrapped tokens after the rebalance
            // occurs
            IERC4626(address(wrappedToken)).mint(amountIn, address(vault));
            vault.settle(wrappedToken);
        }
    }

    function _swapHook(
        SwapParams memory params
    ) internal returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) {
        (amountCalculated, amountIn, amountOut) = getVault().swap(params);
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
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external pure returns (uint256) {
        // This pool doesn't support single token add/remove liquidity, so this function is not needed.
        // Should never get here, but need to implement the interface.
        return balancesLiveScaled18[tokenInIndex].mulDown(invariantRatio);
    }

    /// @inheritdoc IPoolLiquidity
    function onRemoveLiquidityCustom(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external pure returns (uint256, uint256[] memory, uint256[] memory, bytes memory) {
        // Should throw `DoesNotSupportRemoveLiquidityCustom` before getting here, but need to implement the interface.
        revert IVaultErrors.OperationNotSupported();
    }
}
