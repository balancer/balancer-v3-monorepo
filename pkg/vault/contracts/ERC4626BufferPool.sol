// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IBufferPool, RebalanceHookParams } from "@balancer-labs/v3-interfaces/contracts/vault/IBufferPool.sol";
import {
    AddLiquidityKind,
    RemoveLiquidityKind,
    SwapParams as VaultSwapParams,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { BasePoolAuthentication } from "./BasePoolAuthentication.sol";
import { BalancerPoolToken } from "./BalancerPoolToken.sol";
import { BasePoolHooks } from "./BasePoolHooks.sol";

/**
 * @notice ERC4626 Buffer Pool, designed to be used internally for ERC4626 token types in standard pools.
 * @dev These "pools" reuse the code for pools, but are not registered with the Vault, guaranteeing they
 * cannot be used externally. To the outside world, they don't exist.
 */
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

    uint256 public constant WRAPPED_TOKEN_INDEX = 0;
    uint256 public constant BASE_TOKEN_INDEX = 1;

    // Due to rounding issues, the swap operation of the rebalance function can miss the amount of tokens by 1 or 2.
    // These extra tokens are sent to the pool balances or stays in the buffer contract, when the swap is settled.
    // We are limiting the amount of this error to 2 units of the wrapped token.
    uint256 public constant MAXIMUM_DIFF_WTOKENS = 2;

    IERC4626 internal immutable _wrappedToken;
    uint256 internal immutable _wrappedTokenScalingFactor;
    uint256 internal immutable _baseTokenScalingFactor;

    // Uses the factory as the Authentication disambiguator.
    constructor(
        string memory name,
        string memory symbol,
        IERC4626 wrappedToken,
        IVault vault
    ) BalancerPoolToken(vault, name, symbol) BasePoolAuthentication(vault, msg.sender) {
        _wrappedToken = wrappedToken;
        ERC20 baseToken = ERC20(wrappedToken.asset());
        _wrappedTokenScalingFactor = 10 ** (18 - wrappedToken.decimals());
        _baseTokenScalingFactor = 10 ** (18 - baseToken.decimals());
    }

    /// @inheritdoc IBasePool
    function getPoolTokens() public view onlyVault returns (IERC20[] memory tokens) {
        return getVault().getPoolTokens(address(this));
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
        return kind == AddLiquidityKind.CUSTOM;
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

        amountsInScaled18 = BasePoolMath.computeProportionalAmountsIn(balancesScaled18, bptAmountOut, totalSupply());
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
        return kind == RemoveLiquidityKind.PROPORTIONAL;
    }

    /// @inheritdoc BasePoolHooks
    function onBeforeSwap(IBasePool.SwapParams calldata) external view override onlyVault returns (bool) {
        // Swaps cannot be called externally - only the Vault can call this.
        // Since routers might still try to trade directly with buffer pools (either maliciously or accidentally),
        // the Vault also explicitly blocks any swaps with buffer pools.

        // TODO implement - check for / perform rebalancing; call _rebalance() if needed
        // Exact mechanism TBD. Might call back to the Vault with a special operation (that can only be called from
        // a Buffer Pool) to move the token balances, asset manager style.
        return true;
    }

    /// @inheritdoc IBasePool
    function onSwap(IBasePool.SwapParams memory request) public view onlyVault returns (uint256) {
        // If onSwap was triggered by the rebalance function, use the rate (expensive, but more precise)
        // Since the rebalance function is the only one marked non-reentrant, we can use that guard directly.
        // Note that this ReentrancyGuard is local to the pool, not related to the Vault's separate ReentrancyGuard.
        // NB: If this ever changes, we would need to create another modifier on the rebalance function and check that.
        if (_reentrancyGuardEntered()) {
            // Rate used by the vault to scale values
            uint256 wrappedRate = _getRate();

            uint256 unscaledSharesAmount = request.amountGivenScaled18.divDown(wrappedRate) /
                _wrappedTokenScalingFactor;
            // Add 1 to assets amount so we make sure we're always returning more assets than needed to wrap.
            // It ensures that any error in the calculation of the rate will be charged from the buffer,
            // and not from the vault
            uint256 unscaledAssetsAmount = _wrappedToken.previewRedeem(unscaledSharesAmount) + 1;
            uint256 preciseAmountScaled18 = unscaledAssetsAmount * _wrappedTokenScalingFactor;

            // amountGivenScaled18 has some imprecision when calculating the rate (we store only 18 decimals of rate,
            // therefore it's less precise than using preview or convertToAssets directly).
            // So, we need to return the linear math value (amountGivenScaled18), but add the error introduced by
            // the rate difference, which is calculated by (amountGivenScaled18 - preciseAmountScaled18), i.e.:
            //
            // amountGivenScaled18 + (error)
            //
            //     where error is (amountGivenScaled18 - preciseAmountScaled18)
            return 2 * request.amountGivenScaled18 - preciseAmountScaled18;
        } else {
            // If onSwap wasn't triggered by the rebalance function, use linear math
            return request.amountGivenScaled18;
        }
    }

    /// @inheritdoc IBasePool
    function computeInvariant(uint256[] memory balancesLiveScaled18) public view onlyVault returns (uint256) {
        return balancesLiveScaled18[WRAPPED_TOKEN_INDEX] + balancesLiveScaled18[BASE_TOKEN_INDEX];
    }

    /// @inheritdoc IRateProvider
    function getRate() external view onlyVault returns (uint256) {
        return _getRate();
    }

    /// @inheritdoc IBufferPool
    function rebalance() external authenticate {
        _rebalance();
    }

    /// @dev Non-reentrant to ensure we don't try to externally rebalance during an internal rebalance.
    function _rebalance() internal nonReentrant {
        address poolAddress = address(this);

        // Get balance of tokens
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, uint256[] memory decimalScalingFactors, ) = getVault()
            .getPoolTokenInfo(poolAddress);

        // PreviewRedeem converts a wrapped amount into a base amount
        uint256 balanceWrappedAssets = _wrappedToken.previewRedeem(balancesRaw[WRAPPED_TOKEN_INDEX]);
        uint256 balanceUnwrappedAssets = balancesRaw[BASE_TOKEN_INDEX];

        uint256[] memory balancesScaled18 = new uint256[](2);
        balancesScaled18[WRAPPED_TOKEN_INDEX] = balanceWrappedAssets.toScaled18RoundDown(
            decimalScalingFactors[WRAPPED_TOKEN_INDEX]
        );
        balancesScaled18[BASE_TOKEN_INDEX] = balanceUnwrappedAssets.toScaled18RoundDown(
            decimalScalingFactors[BASE_TOKEN_INDEX]
        );

        if (_isBufferPoolBalanced(balancesScaled18)) {
            return;
        }

        uint256 exchangeAmountRaw;
        uint256 limit;
        if (balanceWrappedAssets > balanceUnwrappedAssets) {
            exchangeAmountRaw = (balanceWrappedAssets - balanceUnwrappedAssets) / 2;
            // Since the swap is calculating the amountOut of wrapped tokens,
            // we need to limit the minimum amountOut, which can be defined by
            // the exact conversion of (exchangeAmountRaw - 1), to give some
            // margin for rounding errors related to rate
            limit = _wrappedToken.convertToShares(exchangeAmountRaw - 1) - MAXIMUM_DIFF_WTOKENS;

            getVault().invoke(
                abi.encodeWithSelector(
                    ERC4626BufferPool.rebalanceHook.selector,
                    RebalanceHookParams({
                        sender: msg.sender,
                        kind: SwapKind.EXACT_IN,
                        pool: poolAddress,
                        tokenIn: tokens[BASE_TOKEN_INDEX],
                        tokenOut: tokens[WRAPPED_TOKEN_INDEX],
                        amountGivenRaw: exchangeAmountRaw,
                        limit: limit
                    })
                )
            );
        } else if (balanceUnwrappedAssets > balanceWrappedAssets) {
            exchangeAmountRaw = (balanceUnwrappedAssets - balanceWrappedAssets) / 2;
            // Since the swap is calculating the amountIn of wrapped tokens,
            // we need to limit the maximum amountIn, which can be defined by
            // the exact conversion of (exchangeAmountRaw + 1), to give some
            // margin for rounding errors related to rate
            limit = _wrappedToken.convertToShares(exchangeAmountRaw + 1) + MAXIMUM_DIFF_WTOKENS;

            getVault().invoke(
                abi.encodeWithSelector(
                    ERC4626BufferPool.rebalanceHook.selector,
                    RebalanceHookParams({
                        sender: msg.sender,
                        kind: SwapKind.EXACT_OUT,
                        pool: poolAddress,
                        tokenIn: tokens[WRAPPED_TOKEN_INDEX],
                        tokenOut: tokens[BASE_TOKEN_INDEX],
                        amountGivenRaw: exchangeAmountRaw,
                        limit: limit
                    })
                )
            );
        }
    }

    function rebalanceHook(RebalanceHookParams calldata params) external payable onlyVault {
        (, uint256 amountIn, uint256 amountOut) = _swapHook(params);

        IERC20 baseToken;
        IERC20 wrappedToken;

        if (params.kind == SwapKind.EXACT_IN) {
            baseToken = params.tokenIn;
            wrappedToken = params.tokenOut;

            getVault().wire(wrappedToken, address(this), amountOut);
            IERC4626(address(wrappedToken)).withdraw(amountIn, address(this), address(this));
            baseToken.safeTransfer(address(getVault()), amountIn);
            getVault().settle(baseToken);
        } else {
            baseToken = params.tokenOut;
            wrappedToken = params.tokenIn;

            getVault().wire(baseToken, address(this), amountOut);
            baseToken.approve(address(wrappedToken), amountOut);
            IERC4626(address(wrappedToken)).deposit(amountOut, address(this));
            wrappedToken.safeTransfer(address(getVault()), amountIn);
            getVault().settle(wrappedToken);
        }
    }

    function _swapHook(
        RebalanceHookParams calldata params
    ) internal returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) {
        (amountCalculated, amountIn, amountOut) = getVault().swap(
            VaultSwapParams({
                kind: params.kind,
                pool: params.pool,
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                amountGivenRaw: params.amountGivenRaw,
                limitRaw: params.limit,
                userData: ""
            })
        );
    }

    function _isBufferPoolBalanced(uint256[] memory balancesScaled18) private view returns (bool) {
        if (balancesScaled18[WRAPPED_TOKEN_INDEX] == balancesScaled18[BASE_TOKEN_INDEX]) {
            return true;
        }

        // If not perfectly proportional, makes sure that the difference is within tolerance.
        // The tolerance depends on the decimals of the token, because it introduces imprecision to the rate
        // calculation, and on the initial balance of the pool (since balancesScaled18 has 18 decimals,
        // it's divided by FixedPoint.ONE [mulDown] so we get only the integer part of the number)
        uint256 tolerance = 1;

        if (balancesScaled18[WRAPPED_TOKEN_INDEX] >= balancesScaled18[BASE_TOKEN_INDEX]) {
            if (_wrappedTokenScalingFactor * balancesScaled18[WRAPPED_TOKEN_INDEX] > FixedPoint.ONE) {
                tolerance = _wrappedTokenScalingFactor.mulDown(balancesScaled18[WRAPPED_TOKEN_INDEX]);
            }
            return balancesScaled18[WRAPPED_TOKEN_INDEX] - balancesScaled18[BASE_TOKEN_INDEX] < tolerance;
        } else {
            if (_baseTokenScalingFactor * balancesScaled18[BASE_TOKEN_INDEX] > FixedPoint.ONE) {
                tolerance = _baseTokenScalingFactor.mulDown(balancesScaled18[BASE_TOKEN_INDEX]);
            }
            return balancesScaled18[BASE_TOKEN_INDEX] - balancesScaled18[WRAPPED_TOKEN_INDEX] < tolerance;
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
