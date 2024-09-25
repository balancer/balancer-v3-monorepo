// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IStablePool } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import {
    LiquidityManagement,
    TokenConfig,
    PoolSwapParams,
    HookFlags,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

/**
 * @notice Hook that applies a fee for out of range or undesirable amounts of tokens in relation to a threshold.
 * @dev Uses the dynamic fee mechanism to apply a directional fee.
 */
contract StableSurgeHookExample is BaseHooks, VaultGuard {
    using FixedPoint for uint256;
    // Only pools from a specific factory are able to register and use this hook.
    address private immutable _allowedFactory;
    // Defines the range in which surging will not occur
    mapping(address pool => uint256 threshold) public poolThresholdPercentage;
    // An amplification coefficient to amplify the degree to which a fee increases after the threshold is met.
    mapping(address pool => uint256 surgeCoefficient) public poolSurgeCoefficient;
    uint256 public constant DEFAULT_SURGECOEFFICIENT = 50e18;
    // A threshold of 0.1 for a 2 token pool means surging occurs if any token reaches 60% of the total of balances.
    uint256 public constant DEFAULT_THRESHOLD = 0.1e18;

    // Note on StableSurge calculations:
    // Relevant Variables inherited from Stable Math:
    // n: number of tokens or assets
    // Bi: balance of token in after the swap
    // Wa: Weight after swap is defined as: Bi / SumOfAllTokenBalancesAfterSwap
    // Surging fee will be applied when:
    // Wa > 1/n + _thresholdPercentage
    // Surging fee is calculated as: staticSwapFee * _surgeCoefficient * (Wa/(1/n + _thresholdPercentage))

    /// @notice The sender does not have permission to call a function.
    error SenderNotAllowed();

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
     * @notice The threshold percentage has been changed in a `StableSurgeHookExample` contract.
     * @dev Note, the initial threshold percentage is set on deployment and an event is emitted.
     * @param hooksContract This contract
     * @param thresholdPercentage The new threshold percentage
     */
    event ThresholdPercentageChanged(address indexed hooksContract, uint256 indexed thresholdPercentage);

    /**
     * @notice The surgeCoefficient has been changed in a `StableSurgeHookExample` contract.
     * @dev Note, the initial surgeCoefficient is set on deployment and an event is emitted.
     * @param hooksContract This contract
     * @param surgeCoefficient The new surgeCoefficient
     */
    event SurgeCoefficientChanged(address indexed hooksContract, uint256 indexed surgeCoefficient);

    constructor(IVault vault, address allowedFactory) VaultGuard(vault) {
        _allowedFactory = allowedFactory;
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallComputeDynamicSwapFee = true;
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

        _setThresholdPercentage(pool, DEFAULT_THRESHOLD);
        _setSurgeCoefficient(pool, DEFAULT_SURGECOEFFICIENT);

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
        uint256 weightAfterSwap;
        if (params.kind == SwapKind.EXACT_IN) {
            uint256 amountCalculatedScaled18 = StableMath.computeOutGivenExactIn(
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
            weightAfterSwap = getWeightAfterSwap(
                params.balancesScaled18,
                params.indexIn,
                params.amountGivenScaled18,
                amountCalculatedScaled18
            );
        } else {
            uint256 amountCalculatedScaled18 = StableMath.computeInGivenExactOut(
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
            weightAfterSwap = getWeightAfterSwap(
                params.balancesScaled18,
                params.indexIn,
                amountCalculatedScaled18,
                params.amountGivenScaled18
            );
        }

        uint256 thresholdBoundary = getThresholdBoundary(params.balancesScaled18.length, poolThresholdPercentage[pool]);
        if (weightAfterSwap > thresholdBoundary) {
            return (
                true,
                getSurgeFee(weightAfterSwap, thresholdBoundary, staticSwapFeePercentage, poolSurgeCoefficient[pool])
            );
        } else {
            return (true, staticSwapFeePercentage);
        }
    }

    /**
     * Defines the range in which surging will not occur.
     * @dev An expected value for threshold in a 2 token (n=2) would be 0.1.
     * This would mean surging would occur if any token reaches 60% of the total of balances.
     * @param numberOfAssets Number of assets in the pool.
     * @param thresholdPercentage Thershold percentage value.
     */
    function getThresholdBoundary(uint256 numberOfAssets, uint256 thresholdPercentage) public pure returns (uint256) {
        return FixedPoint.ONE / numberOfAssets + thresholdPercentage;
    }

    /**
     * The weight after swap, used to determine if surge fee should be applied.
     * @param balancesScaled18 Balances of pool
     * @param indexIn Index of token in
     * @param amountInScaled18 Amount in of swap
     * @param amountOutScaled18 Amount out of swap
     */
    function getWeightAfterSwap(
        uint256[] memory balancesScaled18,
        uint256 indexIn,
        uint256 amountInScaled18,
        uint256 amountOutScaled18
    ) public pure returns (uint256) {
        uint256 balancesTotal;
        for (uint256 i = 0; i < balancesScaled18.length; ++i) {
            balancesTotal += balancesScaled18[i];
        }
        uint256 balanceTokenInAfterSwap = balancesScaled18[indexIn] + amountInScaled18;
        uint256 balancesTotalAfterSwap = balancesTotal + amountInScaled18 - amountOutScaled18;
        return balanceTokenInAfterSwap.divDown(balancesTotalAfterSwap);
    }

    /**
     * A fee based on the virtual weights of the tokens.
     * @param weightAfterSwap Weight after swap
     * @param thresholdBoundary Threshold that surge fee will be applied
     * @param swapFeePercentage Pools static swap fee
     * @param surgeCoefficient Amplification coefficient to amplify the degree a fee increases
     */
    function getSurgeFee(
        uint256 weightAfterSwap,
        uint256 thresholdBoundary,
        uint256 swapFeePercentage,
        uint256 surgeCoefficient
    ) public pure returns (uint256) {
        uint256 weightRatio = weightAfterSwap.divDown(thresholdBoundary);
        return swapFeePercentage.mulDown(surgeCoefficient).mulDown(weightRatio);
    }

    // Permissioned functions

    /**
     * @notice Sets the hook threshold percentage.
     * @dev This function must be permissioned.
     */
    function setThresholdPercentage(address pool, uint256 newThresholdPercentage) external {
        if (_vault.getPoolRoleAccounts(pool).swapFeeManager != msg.sender) {
            revert SenderNotAllowed();
        }
        _setThresholdPercentage(pool, newThresholdPercentage);
    }

    /**
     * @notice Sets the hook surgeCoefficient.
     * @dev This function must be permissioned.
     */
    function setSurgeCoefficient(address pool, uint256 newSurgeCoefficient) external {
        if (_vault.getPoolRoleAccounts(pool).swapFeeManager != msg.sender) {
            revert SenderNotAllowed();
        }
        _setSurgeCoefficient(pool, newSurgeCoefficient);
    }

    function _setThresholdPercentage(address pool, uint256 newThresholdPercentage) private {
        // New threshold should be < 1 - 1/number_of_assets - but this is pool specific. How should we handle this? (Same for surge)
        poolThresholdPercentage[pool] = newThresholdPercentage;

        emit ThresholdPercentageChanged(address(this), newThresholdPercentage);
    }

    function _setSurgeCoefficient(address pool, uint256 newSurgeCoefficient) private {
        // baseFee * 𝜇 / (1/n) < 100 would be the test then.
        poolSurgeCoefficient[pool] = newSurgeCoefficient;

        emit SurgeCoefficientChanged(address(this), newSurgeCoefficient);
    }
}
