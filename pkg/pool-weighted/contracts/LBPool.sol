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
import { WeightValidation } from "./lib/WeightValidation.sol";
import { WeightedPool } from "./WeightedPool.sol";

/// @notice Inheriting from WeightedPool is only slightly wasteful (setting 2 immutable weights
///     and _totalTokens, which will not be used later), and it is tremendously helpful for pool
///     validation and any potential future parent class changes.
contract LBPool is WeightedPool, Ownable, BaseHooks {
    using SafeCast for *;

    // Since we have max 2 tokens and the weights must sum to 1, we only need to store one weight
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
    // could spoof the address of the owner, allowing anyone to withdraw LBP proceeds.

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

    /// @dev Indicates that the router that called the Vault is not trusted and should be ignored.
    error RouterNotTrusted();

    constructor(
        NewPoolParams memory params,
        IVault vault,
        address owner,
        bool swapEnabledOnStart,
        address trustedRouter
    ) WeightedPool(params, vault) Ownable(owner) {
        // _NUM_TOKENS == 2 == params.normalizedWeights.length == params.numTokens
        // WeightedPool validates `numTokens == normalizedWeights.length`
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, params.numTokens);

        // Set the trusted router (passed down from the factory).
        _TRUSTED_ROUTER = trustedRouter;

        // `_startGradualWeightChange` validates weights.

        // solhint-disable-next-line not-rely-on-time
        uint32 currentTime = block.timestamp.toUint32();
        _startGradualWeightChange(currentTime, currentTime, params.normalizedWeights, params.normalizedWeights);

        _setSwapEnabled(swapEnabledOnStart);
    }

    function updateWeightsGradually(
        uint256 startTime,
        uint256 endTime,
        uint256[] memory endWeights
    ) external onlyOwner {
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, endWeights.length);
        WeightValidation.validateTwoWeights(endWeights[0], endWeights[1]);

        // Ensure startTime >= now.
        startTime = GradualValueChange.resolveStartTime(startTime, endTime);

        // The SafeCast ensures `endTime` can't overflow.
        _startGradualWeightChange(startTime.toUint32(), endTime.toUint32(), _getNormalizedWeights(), endWeights);
    }

    /**
     * @dev Return start time, end time, and endWeights as an array.
     * Current weights should be retrieved via `getNormalizedWeights()`.
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
     * @notice Enable/disable trading.
     * @dev This is a permissioned function.
     * @param swapEnabled True if trading should be enabled
     */
    function setSwapEnabled(bool swapEnabled) external onlyOwner {
        _setSwapEnabled(swapEnabled);
    }

    function _setSwapEnabled(bool swapEnabled) private {
        _poolState.swapEnabled = swapEnabled;

        emit SwapEnabledSet(swapEnabled);
    }

    /**
     * @notice Indicate whether swaps are enabled or not for the given pool.
     * @return swapEnabled True if trading is enabled
     */
    function getSwapEnabled() external view returns (bool) {
        return _getPoolSwapEnabled();
    }

    function _getPoolSwapEnabled() internal view returns (bool) {
        return _poolState.swapEnabled;
    }

    /*******************************************************************************
                                    Hook Functions
    *******************************************************************************/

    /**
     * @notice Hook to be executed when pool is registered. Returns true if registration was successful, and false to
     * revert the registration of the pool. Make sure this function is properly implemented (e.g. check the factory,
     * and check that the given pool is from the factory).
     *
     * @param factory Address of the pool factory
     * @param pool Address of the pool
     * @return success True if the hook allowed the registration, false otherwise
     */
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public view override onlyVault returns (bool) {
        return (pool == address(this) && IBasePoolFactory(factory).isPoolFromFactory(pool));
    }

    // Return HookFlags struct that indicates which hooks this contract supports
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        // Support hooks before swap/join for swapEnabled/onlyOwner LP
        hookFlags.shouldCallBeforeSwap = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;
    }

    /**
     * @notice Check that the caller who initiated the add liquidity operation is the owner.
     * @param router The address (usually a router contract) that initiated add liquidity operation on the Vault
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
        // TODO use TrustedRoutersProvider. Presumably something like this:
        // if (ITrustedRoutersProvider(TRUSTED_ROUTERS_PROVIDER).isTrusted(router)) {
        if (router == _TRUSTED_ROUTER) {
            //TODO: should hooks w/ failing checks revert or just return false?
            return IRouterCommon(router).getSender() == owner();
        }
        revert RouterNotTrusted();
    }

    /**
     * @notice Called before a swap to let pool block swaps if not enabled.
     * @return success True if the pool has swaps enabled.
     */
    function onBeforeSwap(PoolSwapParams calldata, address) public view override onlyVault returns (bool) {
        return _getPoolSwapEnabled();
    }

    /* =========================================
     * =========================================
     * ==========INTERNAL FUNCTIONS=============
     * =========================================
     * =========================================
     */

    function _getNormalizedWeight0() internal view virtual returns (uint256) {
        PoolState memory poolState = _poolState;
        uint256 pctProgress = _getWeightChangeProgress(poolState);
        return GradualValueChange.interpolateValue(poolState.startWeight0, poolState.endWeight0, pctProgress);
    }

    function _getNormalizedWeight(uint256 tokenIndex) internal view virtual override returns (uint256) {
        uint256 normalizedWeight0 = _getNormalizedWeight0();
        if (tokenIndex == 0) {
            return normalizedWeight0;
        } else if (tokenIndex == 1) {
            return FixedPoint.ONE - normalizedWeight0;
        }
        revert IVaultErrors.InvalidToken();
    }

    function _getNormalizedWeights() internal view override returns (uint256[] memory) {
        uint256[] memory normalizedWeights = new uint256[](_NUM_TOKENS);
        normalizedWeights[0] = _getNormalizedWeight0();
        normalizedWeights[1] = FixedPoint.ONE - normalizedWeights[0];
        return normalizedWeights;
    }

    function _getWeightChangeProgress(PoolState memory poolState) internal view returns (uint256) {
        return GradualValueChange.calculateValueChangeProgress(poolState.startTime, poolState.endTime);
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
        WeightValidation.validateTwoWeights(endWeights[0], endWeights[1]);

        PoolState memory poolState = _poolState;
        poolState.startTime = startTime;
        poolState.endTime = endTime;

        // These have been validated, so can be safely cast directly.
        poolState.startWeight0 = uint64(startWeights[0]);
        poolState.endWeight0 = uint64(endWeights[0]);

        _poolState = poolState;

        emit GradualWeightUpdateScheduled(startTime, endTime, startWeights, endWeights);
    }
}
