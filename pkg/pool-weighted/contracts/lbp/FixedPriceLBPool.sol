// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/IFixedPriceLBPool.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { PoolInfo } from "@balancer-labs/v3-pool-utils/contracts/PoolInfo.sol";

import { LBPValidation } from "./LBPValidation.sol";
import { LBPCommon } from "./LBPCommon.sol";

/**
 * @notice Fixed-price Liquidity Bootstrapping Pool for token sales at a constant rate.
 * @dev Unlike traditional LBPs with changing weights, this pool maintains a constant exchange rate throughout the sale
 * period. The pool uses a simple x + y invariant corresponding to the total value in terms of the reserve token (i.e,
 * token balance * rate + reserve). This avoids the complexity and gas cost of weight adjustments, while still
 * benefiting from Balancer's vault infrastructure.
 *
 * Since all fixed price LBPs are "buy-only," it is "seedless," and must be initialized with project tokens only.
 *
 * Key features:
 * - Constant price throughout the sale period
 * - Simple swap math: multiply or divide by the fixed rate
 * - Simple constant sum invariant: inv = projectBalance * projectTokenRate + reserveBalance
 * - No reserve tokens required on initialization
 */
contract FixedPriceLBPool is IFixedPriceLBPool, LBPCommon, BalancerPoolToken, PoolInfo, Version {
    using FixedPoint for uint256;

    // Fees are 18-decimal, floating point values, which will be stored in the Vault using 24 bits.
    // This means they have 0.00001% resolution (i.e., any non-zero bits < 1e11 will cause precision loss).
    // Since this doesn't use WeightedMath, we don't need a minimum swap fee to keep the math well-behaved.
    // Maximum values protect users by preventing permissioned actors from setting excessively high swap fees.
    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 0;
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 10e16; // 10%

    /**
     * @notice The fixed exchange rate between project and reserve tokens (18 decimals).
     * @dev This represents how many reserve tokens equal one project token.
     * For example, if 1 PROJECT = 4 USDC, then _projectTokenRate = 4e18.
     */
    uint256 private immutable _projectTokenRate;

    constructor(
        LBPCommonParams memory lbpCommonParams,
        FactoryParams memory factoryParams,
        uint256 projectTokenRate
    )
        LBPCommon(
            lbpCommonParams,
            _getEmptyMigrationParams(),
            factoryParams.trustedRouter,
            address(0), // no migration router
            factoryParams.secondaryHookContract
        )
        BalancerPoolToken(factoryParams.vault, lbpCommonParams.name, lbpCommonParams.symbol)
        PoolInfo(factoryParams.vault)
        Version(factoryParams.poolVersion)
    {
        if (projectTokenRate == 0) {
            revert InvalidProjectTokenRate();
        }

        if (lbpCommonParams.blockProjectTokenSwapsIn == false) {
            revert TokenSwapsInUnsupported();
        }

        _projectTokenRate = projectTokenRate;
    }

    // wake-disable-next-line missing-return
    function _getEmptyMigrationParams() private pure returns (MigrationParams memory params) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IFixedPriceLBPool
    function getProjectTokenRate() external view returns (uint256) {
        return _projectTokenRate;
    }

    /// @inheritdoc IFixedPriceLBPool
    function getFixedPriceLBPoolDynamicData() external view returns (FixedPriceLBPoolDynamicData memory data) {
        data.balancesLiveScaled18 = _vault.getCurrentLiveBalances(address(this));
        data.staticSwapFeePercentage = _vault.getStaticSwapFeePercentage((address(this)));
        data.totalSupply = totalSupply();

        PoolConfig memory poolConfig = _vault.getPoolConfig(address(this));
        data.isPoolInitialized = poolConfig.isPoolInitialized;
        data.isPoolPaused = poolConfig.isPoolPaused;
        data.isPoolInRecoveryMode = poolConfig.isPoolInRecoveryMode;
        data.isSwapEnabled = _isSwapEnabled();
    }

    /// @inheritdoc IFixedPriceLBPool
    function getFixedPriceLBPoolImmutableData() external view returns (FixedPriceLBPoolImmutableData memory data) {
        data.tokens = _vault.getPoolTokens(address(this));
        data.projectTokenIndex = _projectTokenIndex;
        data.reserveTokenIndex = _reserveTokenIndex;

        (data.decimalScalingFactors, ) = _vault.getPoolTokenRates(address(this));
        data.startTime = _startTime;
        data.endTime = _endTime;

        data.projectTokenRate = _projectTokenRate;
    }

    /*******************************************************************************
                                    Base Pool Hooks
    *******************************************************************************/

    /// @inheritdoc IBasePool
    function onSwap(PoolSwapParams memory request) public view override returns (uint256 amountCalculatedScaled18) {
        // Block if the sale has not started or has ended.
        if (_isSwapEnabled() == false) {
            revert SwapsDisabled();
        }

        // Project token must be the token out.
        if (request.indexIn == _projectTokenIndex) {
            revert SwapOfProjectTokenIn();
        }

        // Calculated amount is amount out; round down to favor the Vault.
        // When buying project (reserve in): amountOut = amountIn / rate
        // When selling project (project in): amountOut = amountIn * rate
        amountCalculatedScaled18 = request.kind == SwapKind.EXACT_IN
            ? request.amountGivenScaled18.divDown(_projectTokenRate)
            : request.amountGivenScaled18.mulUp(_projectTokenRate);
    }

    /**
     * @notice Compute the pool invariant.
     * @dev The invariant is: inv = projectBalance * projectTokenRate + reserveBalance.
     * This represents the total value in the pool, in terms of reserve tokens.
     *
     * @param balances The current pool balances (in 18-decimal scaling)
     * @param rounding The rounding direction (up or down)
     * @return invariant The calculated invariant value
     */
    function computeInvariant(uint256[] memory balances, Rounding rounding) public view returns (uint256 invariant) {
        // inv = projectBalance * rate + reserveBalance
        uint256 projectTokenValue = rounding == Rounding.ROUND_UP
            ? balances[_projectTokenIndex].mulUp(_projectTokenRate)
            : balances[_projectTokenIndex].mulDown(_projectTokenRate);

        invariant = projectTokenValue + balances[_reserveTokenIndex];
    }

    /// @inheritdoc IBasePool
    function computeBalance(uint256[] memory, uint256, uint256) external pure returns (uint256) {
        // This is unused in these pools.
        revert UnsupportedOperation();
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMinimumSwapFeePercentage() external pure returns (uint256) {
        return _MIN_SWAP_FEE_PERCENTAGE;
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMaximumSwapFeePercentage() external pure returns (uint256) {
        return _MAX_SWAP_FEE_PERCENTAGE;
    }

    /**
     * @inheritdoc IUnbalancedLiquidityInvariantRatioBounds
     * @dev Since this pool only allows balanced liquidity operations (owner adds before sale, anyone removes after),
     * unbalanced operations should never occur. We return extreme bounds to indicate this.
     */
    function getMinimumInvariantRatio() external pure returns (uint256) {
        // No minimum - unbalanced adds are blocked by hooks anyway
        return 0;
    }

    /**
     * @inheritdoc IUnbalancedLiquidityInvariantRatioBounds
     * @dev Since this pool only allows balanced liquidity operations (owner adds before sale, anyone removes after),
     * unbalanced operations should never occur. We return extreme bounds to indicate this.
     */
    function getMaximumInvariantRatio() external pure returns (uint256) {
        // No maximum - unbalanced adds are blocked by hooks anyway
        return type(uint256).max;
    }

    /*******************************************************************************
                                      Pool Hooks
    *******************************************************************************/

    /**
     * @notice Block initialization if the sale has already started, verify sender, and validate amounts.
     * @dev Take care to set the start time far enough in advance to allow for funding; otherwise the pool will remain
     * unfunded and need to be redeployed. Note that initialization does not pass the router address, so we cannot
     * directly check that here, though there has to be a call on the trusted router for its `getSender` to be
     * non-zero.
     *
     * @param exactAmountsInScaled18 The amounts being used to initialize the pool (18-decimal scaled)
     * @return success Always true: allow the initialization to proceed if all conditions have been met
     */
    function onBeforeInitialize(
        uint256[] memory exactAmountsInScaled18,
        bytes memory
    ) public view override onlyBeforeSale returns (bool) {
        // Verify the sender is the owner through the trusted router
        if (ISenderGuard(_trustedRouter).getSender() != owner()) {
            return false;
        }

        uint256 projectAmount = exactAmountsInScaled18[_projectTokenIndex];
        uint256 reserveAmount = exactAmountsInScaled18[_reserveTokenIndex];

        // One-way pool: only buying project tokens with reserve.
        // Therefore, there is no point adding reserve tokens, as they will never be tokenOut in a swap.
        // This is a form of "seedless" LBP; easy because the math is very simple.
        if (projectAmount == 0 || reserveAmount != 0) {
            revert InvalidInitializationAmount();
        }

        return true;
    }
}
