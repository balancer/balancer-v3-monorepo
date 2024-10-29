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

/**
 * @notice Hook that charges a fee on trades that push a pool into an imbalanced state beyond a given threshold.
 * @dev Uses the dynamic fee mechanism to apply a directional fee.
 */
contract StableSurgeHookExample is BaseHooks, VaultGuard {
    using FixedPoint for uint256;

    uint256 public constant MAX_SURGE_FEE_PERCENTAGE = 95e16; // 95%

    // Only pools from a specific factory (e.g., StablePoolFactory) are able to register and use this hook.
    address private immutable _allowedFactory;

    // The default threshold, above which surging will occur.
    uint256 private immutable _defaultSurgeThresholdPercentage;

    // Store the current threshold for each pool.
    mapping(address pool => uint256 threshold) private _surgeThresholdPercentage;

    /**
     * @notice A new `StableSurgeHookExample` contract has been registered successfully.
     * @dev If the registration fails the call will revert, so there will be no event.
     * @param hooksContract This contract
     * @param factory The factory (must be the allowed factory, or the call will revert)
     * @param pool The pool on which the hook was registered
     */
    event StableSurgeHookExampleRegistered(
        address indexed hooksContract,
        address indexed factory,
        address indexed pool
    );

    /**
     * @notice The threshold percentage has been changed for a pool in a `StableSurgeHookExample` contract.
     * @dev Note, the initial threshold percentage is set on deployment and an event is emitted.
     * @param hooksContract This contract
     * @param newSurgeThresholdPercentage The new threshold percentage
     */
    event ThresholdSurgePercentageChanged(address indexed hooksContract, uint256 indexed newSurgeThresholdPercentage);

    /// @notice The sender does not have permission to call a function.
    error SenderNotAllowed();

    /// @notice The threshold must be a valid percentage value.
    error InvalidSurgeThresholdPercentage();

    constructor(IVault vault, address allowedFactory, uint256 defaultSurgeThresholdPercentage) VaultGuard(vault) {
        _ensureValidPercentage(defaultSurgeThresholdPercentage);

        _allowedFactory = allowedFactory;
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

    /// @inheritdoc IHooks
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public override onlyVault returns (bool) {
        // This hook implements a restrictive approach, where we check if the factory is an allowed factory and if
        // the pool was created by the allowed factory.
        emit StableSurgeHookExampleRegistered(address(this), factory, pool);

        // Initially set the pool threshold to the default (can be changed by the pool swapFeeManager in the future).
        _setSurgeThresholdPercentage(pool, _defaultSurgeThresholdPercentage);

        return factory == _allowedFactory && IBasePoolFactory(factory).isPoolFromFactory(pool);
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

    struct SurgeFeeLocals {
        uint256 numTokens;
        uint256 balancedPercentage;
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
        SurgeFeeLocals memory locals;

        locals.numTokens = params.balancesScaled18.length;
        locals.balancedPercentage = FixedPoint.ONE / locals.numTokens;

        uint256[] memory newBalances = new uint256[](locals.numTokens);
        uint256 oldTotalBalance;
        uint256 newTotalBalance;

        for (uint256 i = 0; i < locals.numTokens; ++i) {
            oldTotalBalance += params.balancesScaled18[i];

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

        if (params.kind == SwapKind.EXACT_IN) {
            newTotalBalance = oldTotalBalance + params.amountGivenScaled18 - amountCalculatedScaled18;
        } else {
            newTotalBalance = oldTotalBalance + amountCalculatedScaled18 - params.amountGivenScaled18;
        }

        (uint256 newTotalImbalance, uint256 swapTokenSum) = _computeTotalImbalance(
            newBalances,
            newTotalBalance,
            locals.balancedPercentage,
            params
        );

        // If we are balanced, or the balance has improved, do not surge: simply return the regular fee percentage.
        if (newTotalImbalance == 0) {
            return staticFeePercentage;
        }

        (uint256 oldTotalImbalance, ) = _computeTotalImbalance(
            params.balancesScaled18,
            oldTotalBalance,
            locals.balancedPercentage,
            params
        );

        if (newTotalImbalance <= oldTotalImbalance) {
            return staticFeePercentage;
        }

        // `newTotalImbalance` is non-zero and greater than the old total imbalance. Things have gotten worse,
        // so surging is possible. Check against the threshold.
        uint256 pctImbalance = swapTokenSum.divDown(newTotalImbalance);
        if (pctImbalance <= surgeThresholdPercentage) {
            return staticFeePercentage;
        }

        // surgeFee = staticFee + (maxFee - staticFee) * (pctImbalance - pctThreshold) / (1 - pctThreshold).
        return
            staticFeePercentage +
            (MAX_SURGE_FEE_PERCENTAGE - staticFeePercentage).mulDown(
                (pctImbalance - surgeThresholdPercentage).divDown(surgeThresholdPercentage.complement())
            );
    }

    function _computeTotalImbalance(
        uint256[] memory balances,
        uint256 totalBalance,
        uint256 balancedPercentage,
        PoolSwapParams calldata params
    ) private pure returns (uint256 totalImbalance, uint256 swapTokenSum) {
        for (uint256 i = 0; i < balances.length; ++i) {
            uint256 tokenPercentage = balances[i].divDown(totalBalance);
            uint256 tokenImbalance;

            unchecked {
                if (tokenPercentage > balancedPercentage) {
                    tokenImbalance = tokenPercentage - balancedPercentage;
                } else {
                    tokenImbalance = balancedPercentage - tokenPercentage;
                }
            }

            totalImbalance += tokenImbalance;
            if (i == params.indexIn || i == params.indexOut) {
                swapTokenSum += tokenImbalance;
            }
        }
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

    /// @dev Assumes the percentage value has been externally validated (e.g., with `_ensureValidPercentage`).
    function _setSurgeThresholdPercentage(address pool, uint256 newSurgeThresholdPercentage) private {
        _surgeThresholdPercentage[pool] = newSurgeThresholdPercentage;

        emit ThresholdSurgePercentageChanged(address(this), newSurgeThresholdPercentage);
    }

    function _ensureValidPercentage(uint256 percentage) private pure {
        if (percentage > FixedPoint.ONE) {
            revert InvalidSurgeThresholdPercentage();
        }
    }
}
