// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

import { GradualValueChange } from "./lib/GradualValueChange.sol";
import { WeightedPool } from "./WeightedPool.sol";

/**
 * @notice Weighted Pool with mutable weights, designed to support v3 Liquidity Bootstrapping.
 * @dev Inheriting from WeightedPool is only slightly wasteful (setting 2 immutable weights and `_totalTokens`,
 * which will not be used later), and it is tremendously helpful for pool validation and any potential future
 * base contract changes.
 */
contract LBPool is WeightedPool, Ownable, BaseHooks {
    using SafeCast for *;

    // Since we have max 2 tokens and the weights must sum to 1, we only need to store one weight.
    // Weights are 18 decimal floating point values, which fit in less than 64 bits. Store smaller numeric values
    // to ensure the PoolState fits in a single slot.
    struct PoolState {
        uint32 startTime;
        uint32 endTime;
        uint64 startWeight0;
        uint64 endWeight0;
        bool swapEnabled;
    }
    // `{start,end}Time` are `uint32`s. Ensure that no input time (passed as `uint256`) will overflow.
    uint256 private constant _MAX_TIMESTAMP = type(uint32).max;

    // LBPs are constrained to two tokens.auto
    uint256 private constant _NUM_TOKENS = 2;

    // LBPools are deployed with the Balancer standard router address, which we know reliably reports the true
    // originating account on operations. This is important for liquidity operations, as these are permissioned
    // operations that can only be performed by the owner of the pool. Without this check, a malicious router
    // could spoof the address of the owner, allowing anyone to call permissioned functions.

    // solhint-disable-next-line var-name-mixedcase
    address private immutable _TRUSTED_ROUTER;

    PoolState private _poolState;

    /**
     * @notice Emitted when the owner enables or disables swaps.
     * @param swapEnabled True if we are enabling swaps
     */
    event SwapEnabledSet(bool swapEnabled);

    /**
     * @notice Emitted when the owner initiates a gradual weight change (e.g., at the start of the sale).
     * @dev Also emitted on deployment, recording the initial state.
     * @param startTime The starting timestamp of the update
     * @param endTime  The ending timestamp of the update
     * @param startWeights The weights at the start of the update
     * @param endWeights The final weights after the update is completed
     */
    event GradualWeightUpdateScheduled(
        uint256 startTime,
        uint256 endTime,
        uint256[] startWeights,
        uint256[] endWeights
    );

    /// @dev Indicates that the router that called the Vault is not trusted, so any operations should revert.
    error RouterNotTrusted();

    constructor(
        NewPoolParams memory params,
        IVault vault,
        address owner,
        bool swapEnabledOnStart,
        address trustedRouter
    ) WeightedPool(params, vault) Ownable(owner) {
        // WeightedPool validates `numTokens == normalizedWeights.length`, and ensures valid weights.
        // Here we additionally enforce that LBPs must be two-token pools.
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, params.numTokens);

        // Set the trusted router (passed down from the factory).
        _TRUSTED_ROUTER = trustedRouter;

        // solhint-disable-next-line not-rely-on-time
        uint32 currentTime = block.timestamp.toUint32();
        _startGradualWeightChange(currentTime, currentTime, params.normalizedWeights, params.normalizedWeights);
        _setSwapEnabled(swapEnabledOnStart);
    }

    /**
     * @notice Return start time, end time, and endWeights as an array.
     * @dev Current weights should be retrieved via `getNormalizedWeights()`.
     * @return startTime The starting timestamp of any ongoing weight change
     * @return endTime The ending timestamp of any ongoing weight change
     * @return endWeights The "destination" weights, sorted in token registration order
     */
    function getGradualWeightUpdateParams()
        external
        view
        returns (uint256 startTime, uint256 endTime, uint256[] memory endWeights)
    {
        PoolState memory poolState = _poolState;

        startTime = poolState.startTime;
        endTime = poolState.endTime;

        endWeights = new uint256[](_NUM_TOKENS);
        endWeights[0] = poolState.endWeight0;
        endWeights[1] = FixedPoint.ONE - poolState.endWeight0;
    }

    /**
     * @notice Indicate whether swaps are enabled or not for the given pool.
     * @return swapEnabled True if trading is enabled
     */
    function getSwapEnabled() external view returns (bool) {
        return _getPoolSwapEnabled();
    }

    /*******************************************************************************
                                Permissioned Functions
    *******************************************************************************/

    /**
     * @notice Enable/disable trading.
     * @dev This is a permissioned function that can only be called by the owner.
     * @param swapEnabled True if trading should be enabled
     */
    function setSwapEnabled(bool swapEnabled) external onlyOwner {
        _setSwapEnabled(swapEnabled);
    }

    /**
     * @notice Start a gradual weight change. Weights will change smoothly from current values to `endWeights`.
     * @dev This is a permissioned function that can only be called by the owner.
     * If the `startTime` is in the past, the weight change will begin immediately.
     *
     * @param startTime The timestamp when the weight change will start
     * @param endTime  The timestamp when the weights will reach their final values
     * @param endWeights The final values of the weights
     */
    function updateWeightsGradually(
        uint256 startTime,
        uint256 endTime,
        uint256[] memory endWeights
    ) external onlyOwner {
        _ensureValidWeights(endWeights);

        // Ensure startTime >= now.
        startTime = GradualValueChange.resolveStartTime(startTime, endTime);

        // The SafeCast ensures `endTime` can't overflow.
        _startGradualWeightChange(startTime.toUint32(), endTime.toUint32(), _getNormalizedWeights(), endWeights);
    }

    /*******************************************************************************
                                    Hook Functions
    *******************************************************************************/

    /**
     * @notice Hook to be executed when pool is registered.
     * @dev Returns true if registration was successful, and false to revert the registration of the pool.
     * @param pool Address of the pool
     * @return success True if the hook allowed the registration, false otherwise
     */
    function onRegister(
        address,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public view override onlyVault returns (bool) {
        // Since in this case the pool is the hook, we don't need to check anything else.
        // We *could* check that it's two tokens, but better to let that be caught later, as it will fail with a more
        // descriptive error.
        return pool == address(this);
    }

    // Return HookFlags struct that indicates which hooks this contract supports
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        // Check whether swaps are enabled in `onBeforeSwap`.
        hookFlags.shouldCallBeforeSwap = true;
        // Ensure the caller is the owner, as only the owner can add liquidity.
        hookFlags.shouldCallBeforeAddLiquidity = true;
    }

    /**
     * @notice Check that the caller who initiated the add liquidity operation is the owner.
     * @dev We first ensure the caller is the standard router, so that we know we can trust the value it returns
     * from `getSender`.
     *
     * @param router The address (usually a router contract) that initiated the add liquidity operation
     */
    function onBeforeAddLiquidity(
        address router,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) public view override onlyVault returns (bool) {
        if (router == _TRUSTED_ROUTER) {
            return IRouterCommon(router).getSender() == owner();
        }

        revert RouterNotTrusted();
    }

    /**
     * @notice Called before a swap to let the pool block swaps if not enabled.
     * @return success True if the pool has swaps enabled.
     */
    function onBeforeSwap(PoolSwapParams calldata, address) public view override onlyVault returns (bool) {
        return _getPoolSwapEnabled();
    }

    /*******************************************************************************
                                  Internal Functions
    *******************************************************************************/

    // This is unused in this contract, but must be overridden from WeightedPool for consistency.
    function _getNormalizedWeight(uint256 tokenIndex) internal view virtual override returns (uint256) {
        if (tokenIndex < _NUM_TOKENS) {
            return _getNormalizedWeights()[tokenIndex];
        }

        revert IVaultErrors.InvalidToken();
    }

    function _getNormalizedWeights() internal view override returns (uint256[] memory) {
        uint256[] memory normalizedWeights = new uint256[](_NUM_TOKENS);
        normalizedWeights[0] = _getNormalizedWeight0();
        normalizedWeights[1] = FixedPoint.ONE - normalizedWeights[0];

        return normalizedWeights;
    }

    function _getNormalizedWeight0() internal view virtual returns (uint256) {
        PoolState memory poolState = _poolState;
        uint256 pctProgress = GradualValueChange.calculateValueChangeProgress(poolState.startTime, poolState.endTime);

        return GradualValueChange.interpolateValue(poolState.startWeight0, poolState.endWeight0, pctProgress);
    }

    function _getPoolSwapEnabled() private view returns (bool) {
        return _poolState.swapEnabled;
    }

    function _setSwapEnabled(bool swapEnabled) private {
        _poolState.swapEnabled = swapEnabled;

        emit SwapEnabledSet(swapEnabled);
    }

    /**
     * @dev When calling updateWeightsGradually again during an update, reset the start weights to the current weights,
     * if necessary.
     */
    function _startGradualWeightChange(
        uint32 startTime,
        uint32 endTime,
        uint256[] memory startWeights,
        uint256[] memory endWeights
    ) internal virtual {
        PoolState memory poolState = _poolState;

        poolState.startTime = startTime;
        poolState.endTime = endTime;

        // These have been validated, but SafeCast anyway out of an abundance of caution.
        poolState.startWeight0 = startWeights[0].toUint64();
        poolState.endWeight0 = endWeights[0].toUint64();

        _poolState = poolState;

        emit GradualWeightUpdateScheduled(startTime, endTime, startWeights, endWeights);
    }

    /**
     * @dev Ensure the given set of weights sums to exactly FixedPoint.ONE, and neither of the weights is below
     * the minimum.
     */
    function _ensureValidWeights(uint256[] memory normalizedWeights) internal pure {
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, normalizedWeights.length);

        // Ensure each normalized weight is above the minimum
        uint256 normalizedSum = 0;
        for (uint8 i = 0; i < _NUM_TOKENS; ++i) {
            uint256 normalizedWeight = normalizedWeights[i];

            if (normalizedWeight < _MIN_WEIGHT) {
                revert MinWeight();
            }
            normalizedSum += normalizedWeight;
        }

        // Ensure that the normalized weights sum to ONE
        if (normalizedSum != FixedPoint.ONE) {
            revert NormalizedWeightInvariant();
        }
    }
}
