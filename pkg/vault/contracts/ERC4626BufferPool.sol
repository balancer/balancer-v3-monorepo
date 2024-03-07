// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

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

    // Due to rounding issues, the swap operation in a rebalance can miscalculate token amounts by 1 or 2.
    // When the swap is settled, these extra tokens are either added to the pool balance or are left behind
    // in the buffer contract as dust, to fund subsequent operations.
    uint256 public constant DUST_BUFFER = 2;

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
        _wrappedTokenScalingFactor = ScalingHelpers.computeScalingFactor(IERC20(address(wrappedToken)));
        _baseTokenScalingFactor = ScalingHelpers.computeScalingFactor(IERC20(wrappedToken.asset()));
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
            uint256 wrappedRate = _getRate(FixedPoint.ONE);

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

    /// @inheritdoc IBasePool
    function computeInvariant(uint256[] memory balancesLiveScaled18) public view onlyVault returns (uint256) {
        return balancesLiveScaled18[WRAPPED_TOKEN_INDEX] + balancesLiveScaled18[BASE_TOKEN_INDEX];
    }

    /// @inheritdoc BalancerPoolToken
    function getRate(uint256 shares) external view override onlyVault returns (uint256) {
        return _getRate(shares);
    }

    /// @inheritdoc IBufferPool
    function rebalance() external authenticate {
        _rebalance();
    }

    /// @dev Non-reentrant to ensure we don't try to externally rebalance during an internal rebalance.
    function _rebalance() internal nonReentrant {
        address poolAddress = address(this);
        IVault vault = getVault();

        // Get balance of tokens
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, uint256[] memory decimalScalingFactors, ) = vault
            .getPoolTokenInfo(poolAddress);

        // PreviewRedeem converts a wrapped amount into a base amount
        uint256 balanceWrappedAssetsRaw = _wrappedToken.previewRedeem(balancesRaw[WRAPPED_TOKEN_INDEX]);
        uint256 balanceBaseAssetsRaw = balancesRaw[BASE_TOKEN_INDEX];

        uint256[] memory balancesScaled18 = new uint256[](2);
        // "toScaled18RoundDown" is a "mulDown", and since the balance is divided by FixedPoint.ONE,
        // solidity always rounds down.
        balancesScaled18[WRAPPED_TOKEN_INDEX] = balanceWrappedAssetsRaw.toScaled18RoundDown(
            decimalScalingFactors[WRAPPED_TOKEN_INDEX]
        );
        balancesScaled18[BASE_TOKEN_INDEX] = balanceBaseAssetsRaw.toScaled18RoundDown(
            decimalScalingFactors[BASE_TOKEN_INDEX]
        );

        if (_isBufferPoolBalanced(balancesScaled18)) {
            return;
        }

        uint256 exchangeAmountRaw;
        uint256 limitRaw;
        if (balanceWrappedAssetsRaw > balanceBaseAssetsRaw) {
            exchangeAmountRaw = (balanceWrappedAssetsRaw - balanceBaseAssetsRaw) / 2;
            // Since onSwap will consider a slightly bigger rate for the wrapped token, we need to account that
            // in the minimum limit of amountOut calculation, and that's why (exchangeAmountRaw - 2) is converted.
            // Also, since the unwrap operation has RoundDown divisions, DUST_BUFFER needs to be subtracted
            // from amountOut too
            limitRaw = _wrappedToken.convertToShares(exchangeAmountRaw - DUST_BUFFER) - DUST_BUFFER;

            // In this case, since there is more wrapped than base assets, wrapped tokens will be removed (tokenOut)
            // and then unwrapped, and the resulting base assets will be deposited in the pool (tokenIn)
            vault.lock(
                abi.encodeWithSelector(
                    ERC4626BufferPool.rebalanceHook.selector,
                    VaultSwapParams({
                        kind: SwapKind.EXACT_IN,
                        pool: poolAddress,
                        tokenIn: tokens[BASE_TOKEN_INDEX],
                        tokenOut: tokens[WRAPPED_TOKEN_INDEX],
                        amountGivenRaw: exchangeAmountRaw,
                        limitRaw: limitRaw,
                        userData: ""
                    })
                )
            );
        } else if (balanceBaseAssetsRaw > balanceWrappedAssetsRaw) {
            exchangeAmountRaw = (balanceBaseAssetsRaw - balanceWrappedAssetsRaw) / 2;
            // Since onSwap will consider a slightly bigger rate for the wrapped token, we need to account that
            // in the maximum limit of amountIn calculation, and that's why (exchangeAmountRaw + 2) is converted.
            // Also, since the wrap operation has RoundDown divisions, DUST_BUFFER needs to be added
            // to amountIn too
            limitRaw = _wrappedToken.convertToShares(exchangeAmountRaw + DUST_BUFFER) + DUST_BUFFER;

            // In this case, since there is more base than wrapped assets, base assets will be removed (tokenOut)
            // and then wrapped, and the resulting wrapped assets will be deposited in the pool (tokenIn)
            vault.lock(
                abi.encodeWithSelector(
                    ERC4626BufferPool.rebalanceHook.selector,
                    VaultSwapParams({
                        kind: SwapKind.EXACT_OUT,
                        pool: poolAddress,
                        tokenIn: tokens[WRAPPED_TOKEN_INDEX],
                        tokenOut: tokens[BASE_TOKEN_INDEX],
                        amountGivenRaw: exchangeAmountRaw,
                        limitRaw: limitRaw,
                        userData: ""
                    })
                )
            );
        }
    }

    function rebalanceHook(VaultSwapParams calldata params) external payable onlyVault {
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
        VaultSwapParams calldata params
    ) internal returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) {
        (amountCalculated, amountIn, amountOut) = getVault().swap(
            VaultSwapParams({
                kind: params.kind,
                pool: params.pool,
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                amountGivenRaw: params.amountGivenRaw,
                limitRaw: params.limitRaw,
                userData: params.userData
            })
        );
    }

    function _isBufferPoolBalanced(uint256[] memory balancesScaled18) private pure returns (bool) {
        if (balancesScaled18[WRAPPED_TOKEN_INDEX] == balancesScaled18[BASE_TOKEN_INDEX]) {
            return true;
        }

        // If not perfectly proportional, makes sure that the difference is within tolerance
        // (0.1% of base token amount to 1 side or the other).
        uint256 tolerance = (balancesScaled18[WRAPPED_TOKEN_INDEX] + balancesScaled18[BASE_TOKEN_INDEX]) / 1000;

        if (balancesScaled18[WRAPPED_TOKEN_INDEX] >= balancesScaled18[BASE_TOKEN_INDEX]) {
            return balancesScaled18[WRAPPED_TOKEN_INDEX] - balancesScaled18[BASE_TOKEN_INDEX] < tolerance;
        } else {
            return balancesScaled18[BASE_TOKEN_INDEX] - balancesScaled18[WRAPPED_TOKEN_INDEX] < tolerance;
        }
    }

    function _getRate(uint256 shares) private view returns (uint256) {
        // TODO: This is really just a placeholder for now. We will need to think more carefully about this.
        // e.g., it will probably need to be scaled according to the asset value decimals. There may be
        // special cases with 0 supply. Wrappers may implement this differently, so maybe we need to calculate
        // the rate directly instead of relying on the wrapper implementation, etc.
        return _wrappedToken.convertToAssets(shares).divDown(shares);
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
