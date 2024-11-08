// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IStablePool } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";
import {
    LiquidityManagement,
    TokenConfig,
    PoolSwapParams,
    HookFlags,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { StableSurgeMedianMath } from "./utils/StableSurgeMedianMath.sol";

/**
 * @notice Hook that charges a fee on trades that push a pool into an imbalanced state beyond a given threshold.
 * @dev Uses the dynamic fee mechanism to apply a directional fee.
 */
contract StableSurgeHookExample is BaseHooks, VaultGuard {
    using FixedPoint for uint256;

    uint256 public constant MAX_SURGE_FEE_PERCENTAGE = 95e16; // 95%

    // The default threshold, above which surging will occur.
    uint256 private immutable _defaultSurgeThresholdPercentage;

    // Store the current threshold for each pool.
    mapping(address pool => uint256 threshold) private _surgeThresholdPercentage;

    /**
     * @notice A new `StableSurgeHookExample` contract has been registered successfully.
     * @dev If the registration fails the call will revert, so there will be no event.
     * @param pool The pool on which the hook was registered
     */
    event StableSurgeHookExampleRegistered(address indexed pool);

    /**
     * @notice The threshold percentage has been changed for a pool in a `StableSurgeHookExample` contract.
     * @dev Note, the initial threshold percentage is set on deployment and an event is emitted.
     * @param pool The pool for which the threshold percentage has been changed
     * @param newSurgeThresholdPercentage The new threshold percentage
     */
    event ThresholdSurgePercentageChanged(address indexed pool, uint256 newSurgeThresholdPercentage);

    /// @notice The sender does not have permission to call a function.
    error SenderNotAllowed();

    /// @notice The threshold must be a valid percentage value.
    error InvalidSurgeThresholdPercentage();

    constructor(IVault vault, uint256 defaultSurgeThresholdPercentage) VaultGuard(vault) {
        _ensureValidPercentage(defaultSurgeThresholdPercentage);

        _defaultSurgeThresholdPercentage = defaultSurgeThresholdPercentage;
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallComputeDynamicSwapFee = true;
    }

    /**
     * @notice Getter for the default surge threshold percentage.
     * @return surgeThresholdPercentage The default surge threshold percentage for this hook contract
     */
    function getDefaultSurgeThresholdPercentage() external view returns (uint256) {
        return _defaultSurgeThresholdPercentage;
    }

    /**
     * @notice Getter for the surge threshold percentage for a pool.
     * @param pool The pool for which the surge threshold percentage is requested
     * @return surgeThresholdPercentage The surge threshold percentage for the pool
     */
    function getSurgeThresholdPercentage(address pool) external view returns (uint256) {
        return _surgeThresholdPercentage[pool];
    }

    /// @inheritdoc IHooks
    function onRegister(
        address,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public override onlyVault returns (bool) {
        emit StableSurgeHookExampleRegistered(pool);

        // Initially set the pool threshold to the default (can be changed by the pool swapFeeManager in the future).
        _setSurgeThresholdPercentage(pool, _defaultSurgeThresholdPercentage);

        return true;
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) public view override onlyVault returns (bool, uint256) {
        uint256 amp;
        (amp, , ) = IStablePool(pool).getAmplificationParameter();

        // In order to calculate `weightAfterSwap` we need balances after swap, so we must compute the swap amount.
        uint256 invariant = StableMath.computeInvariant(amp, params.balancesScaled18);
        uint256 amountCalculatedScaled18;

        if (params.kind == SwapKind.EXACT_IN) {
            amountCalculatedScaled18 = StableMath.computeOutGivenExactIn(
                amp,
                params.balancesScaled18,
                params.indexIn,
                params.indexOut,
                params.amountGivenScaled18,
                invariant
            );

            // Swap fee is always a percentage of the amountCalculated. On ExactIn, subtract it from the calculated
            // amountOut. Round up to avoid losses during precision loss.
            uint256 swapFeeAmountScaled18 = amountCalculatedScaled18.mulUp(staticSwapFeePercentage);
            amountCalculatedScaled18 -= swapFeeAmountScaled18;
        } else {
            amountCalculatedScaled18 = StableMath.computeInGivenExactOut(
                amp,
                params.balancesScaled18,
                params.indexIn,
                params.indexOut,
                params.amountGivenScaled18,
                invariant
            );

            // To ensure symmetry with EXACT_IN, the swap fee used by ExactOut is
            // `amountCalculated * fee% / (100% - fee%)`. Add it to the calculated amountIn. Round up to avoid losses
            // during precision loss.
            uint256 swapFeeAmountScaled18 = amountCalculatedScaled18.mulDivUp(
                staticSwapFeePercentage,
                staticSwapFeePercentage.complement()
            );

            amountCalculatedScaled18 += swapFeeAmountScaled18;
        }

        return (
            true,
            getSurgeFeePercentage(
                params,
                amountCalculatedScaled18,
                _surgeThresholdPercentage[pool],
                staticSwapFeePercentage
            )
        );
    }

    /**
     * @notice Sets the hook threshold percentage.
     * @dev This function must be permissioned. If the pool does not have a swap fee manager role set, the surge
     * threshold will be effectively immutable, set to the default threshold for this hook contract.
     */
    function setSurgeThresholdPercentage(address pool, uint256 newSurgeThresholdPercentage) external {
        if (_vault.getPoolRoleAccounts(pool).swapFeeManager != msg.sender) {
            revert SenderNotAllowed();
        }
        _ensureValidPercentage(newSurgeThresholdPercentage);

        _setSurgeThresholdPercentage(pool, newSurgeThresholdPercentage);
    }

    /**
     * @notice Calculate the surge fee percentage. If below threshold, return the standard static swap fee percentage.
     * @dev It is public to allow it to be called off-chain.
     * @param params Input parameters for the swap (balances needed)
     * @param amountCalculatedScaled18 THe post-swap amountCalculated, assuming the standard fee is charged
     * @param surgeThresholdPercentage The current surge threshold percentage for this pool
     * @param staticFeePercentage The static fee percentage for the pool (default if there is no surge)
     */
    function getSurgeFeePercentage(
        PoolSwapParams calldata params,
        uint256 amountCalculatedScaled18,
        uint256 surgeThresholdPercentage,
        uint256 staticFeePercentage
    ) public pure returns (uint256) {
        uint256 numTokens = params.balancesScaled18.length;

        uint256[] memory newBalances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            newBalances[i] = params.balancesScaled18[i];
            if (i == params.indexIn) {
                if (params.kind == SwapKind.EXACT_IN) {
                    newBalances[i] += params.amountGivenScaled18;
                } else {
                    newBalances[i] += amountCalculatedScaled18;
                }
            } else if (i == params.indexOut) {
                if (params.kind == SwapKind.EXACT_IN) {
                    newBalances[i] -= amountCalculatedScaled18;
                } else {
                    newBalances[i] -= params.amountGivenScaled18;
                }
            }
        }

        uint256 newTotalImbalance = StableSurgeMedianMath.calculateImbalance(newBalances);

        // If we are balanced, or the balance has improved, do not surge: simply return the regular fee percentage.
        if (newTotalImbalance == 0) {
            return staticFeePercentage;
        }

        uint256 oldTotalImbalance = StableSurgeMedianMath.calculateImbalance(params.balancesScaled18);

        if (newTotalImbalance <= oldTotalImbalance || newTotalImbalance <= surgeThresholdPercentage) {
            return staticFeePercentage;
        }

        // surgeFee = staticFee + (maxFee - staticFee) * (pctImbalance - pctThreshold) / (1 - pctThreshold).
        return
            staticFeePercentage +
            (MAX_SURGE_FEE_PERCENTAGE - staticFeePercentage).mulDown(
                (newTotalImbalance - surgeThresholdPercentage).divDown(surgeThresholdPercentage.complement())
            );
    }

    /// @dev Assumes the percentage value has been externally validated (e.g., with `_ensureValidPercentage`).
    function _setSurgeThresholdPercentage(address pool, uint256 newSurgeThresholdPercentage) private {
        _surgeThresholdPercentage[pool] = newSurgeThresholdPercentage;

        emit ThresholdSurgePercentageChanged(pool, newSurgeThresholdPercentage);
    }

    function _ensureValidPercentage(uint256 percentage) private pure {
        if (percentage > FixedPoint.ONE) {
            revert InvalidSurgeThresholdPercentage();
        }
    }
}
