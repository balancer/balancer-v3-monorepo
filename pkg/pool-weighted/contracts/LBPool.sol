// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { WeightedPool } from "./WeightedPool.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    HookFlags,
    TokenConfig,
    AddLiquidityKind,
    LiquidityManagement,
    PoolSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { GradualValueChange } from "./lib/GradualValueChange.sol";
import { WeightValidation } from "./lib/WeightValidation.sol";

/// @notice Inheriting from WeightedPool is only slightly wasteful (setting 2 immutable weights
///     and _totalTokens, which will not be used later), and it is tremendously helpful for pool
///     validation and any potential future parent class changes.
contract LBPool is WeightedPool, Ownable { //TODO is BaseHooks
    // Since we have max 2 tokens and the weights must sum to 1, we only need to store one weight
    struct PoolState {
        uint56 startTime;
        uint56 endTime;
        uint64 startWeight0;
        uint64 endWeight0;
        bool swapEnabled;
    }
    PoolState private _poolState;

    uint256 private constant _NUM_TOKENS = 2;

    // `{start,end}Time` are `uint56`s. Ensure that no input time (passed as `uint256`) will overflow.
    uint256 private constant _MAX_TIME = type(uint56).max;

    address internal immutable TRUSTED_ROUTERS_PROVIDER;
    address internal immutable TRUSTED_ROUTER_TODO_DELETE_ME;

    event SwapEnabledSet(bool swapEnabled);
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
        address trustedRoutersProvider,
        address trustedRouterTodoDeleteMe
    ) WeightedPool(params, vault) Ownable(owner) {
        // _NUM_TOKENS == 2 == params.normalizedWeights.length == params.numTokens
        // WeightedPool validates `numTokens == normalizedWeights.length`
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, params.numTokens);

        // _startGradualWeightChange validates weights

        // Provider address validation performed at the factory level
        TRUSTED_ROUTERS_PROVIDER = trustedRoutersProvider;
        TRUSTED_ROUTER_TODO_DELETE_ME = trustedRouterTodoDeleteMe;

        uint256 currentTime = block.timestamp;
        _startGradualWeightChange(
            uint56(currentTime),
            uint56(currentTime),
            params.normalizedWeights,
            params.normalizedWeights,
            true,
            swapEnabledOnStart
        );
    }

    function updateWeightsGradually(
        uint256 startTime,
        uint256 endTime,
        uint256[] memory endWeights
    ) external onlyOwner {
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, endWeights.length);
        WeightValidation.validateTwoWeights(endWeights[0], endWeights[1]);

        // Ensure startTime >= now
        startTime = GradualValueChange.resolveStartTime(startTime, endTime);

        // Ensure time will not overflow in storage; only check end (startTime <= endTime)
        GradualValueChange.ensureNoTimeOverflow(endTime, _MAX_TIME);

        _startGradualWeightChange(uint56(startTime), uint56(endTime), _getNormalizedWeights(), endWeights, false, true);
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
     */
    function setSwapEnabled(bool swapEnabled) external onlyOwner {
        _poolState.swapEnabled = swapEnabled;
        emit SwapEnabledSet(swapEnabled);
    }

    /**
     * @notice Return whether swaps are enabled or not for the given pool.
     */
    function getSwapEnabled() external view returns (bool) {
        return _getPoolSwapEnabledState();
    }

    /* =========================================
     * =========================================
     * ============HOOK FUNCTIONS===============
     * =========================================
     * =========================================
     */

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
    ) external view onlyVault returns (bool) {
        return (pool == address(this) && IBasePoolFactory(factory).isPoolFromFactory(pool));
    }

    // Return HookFlags struct that indicates which hooks this contract supports
    function getHookFlags() public pure returns (HookFlags memory hookFlags) {
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
    ) external view onlyVault returns (bool) {
        // TODO use TrustedRoutersProvider. Presumably something like this:
        // if (ITrustedRoutersProvider(TRUSTED_ROUTERS_PROVIDER).isTrusted(router)) {
        if (router == TRUSTED_ROUTER_TODO_DELETE_ME) {
            return IRouterCommon(router).getSender() == owner();
        }
        revert RouterNotTrusted(); //TODO: should hooks revert or just return false?
    }

    /**
     * @notice Called before a swap to let pool block swaps if not enabled.
     * @return success True if the pool has swaps enabled.
     */
    function onBeforeSwap(PoolSwapParams calldata, address) public virtual onlyVault returns (bool) {
        return _getPoolSwapEnabledState();
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
        uint56 startTime,
        uint56 endTime,
        uint256[] memory startWeights,
        uint256[] memory endWeights,
        bool modifySwapEnabledStatus,
        bool newSwapEnabled
    ) internal virtual {
        WeightValidation.validateTwoWeights(endWeights[0], endWeights[1]);

        PoolState memory poolState = _poolState;
        poolState.startTime = startTime;
        poolState.endTime = endTime;
        poolState.startWeight0 = uint64(startWeights[0]);
        poolState.endWeight0 = uint64(endWeights[0]);

        if (modifySwapEnabledStatus) {
            poolState.swapEnabled = newSwapEnabled;
            emit SwapEnabledSet(newSwapEnabled);
        }

        _poolState = poolState;
        emit GradualWeightUpdateScheduled(startTime, endTime, startWeights, endWeights);
    }

    function _getPoolSwapEnabledState() internal view returns (bool) {
        return _poolState.swapEnabled;
    }
}
