// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

import { GradualValueChange } from "../lib/GradualValueChange.sol";
import { WeightedPool } from "../WeightedPool.sol";
import { LBPParams } from "./LBPoolFactory.sol";

/**
 * @notice Weighted Pool with mutable weights, designed to support v3 Liquidity Bootstrapping.
 * @dev Inheriting from WeightedPool is only slightly wasteful (setting 2 immutable weights and `_totalTokens`,
 * which will not be used later), and it is tremendously helpful for pool validation and any potential future
 * base contract changes.
 */
contract LBPool is WeightedPool, Ownable2Step, BaseHooks {
    using SafeCast for *;
    address public bootstrapToken;

    uint256 bootstrapTokenIndex;

    bool public allowRemovalOnlyAfterWeightChange;
    bool public restrictSaleOfBootstrapToken;

    // Since we have max 2 tokens and the weights must sum to 1, we only need to store one weight.
    // Weights are 18 decimal floating point values, which fit in less than 64 bits. Store smaller numeric values
    // to ensure the PoolState fits in a single slot. All timestamps in the system are uint32, enforced through
    // SafeCast.
    struct PoolState {
        uint32 startTime;
        uint32 endTime;
        uint64 startWeight0;
        uint64 endWeight0;
    }

    // LBPs are constrained to two tokens.
    uint256 private constant _NUM_TOKENS = 2;

    // LBPools are deployed with the Balancer standard router address, which we know reliably reports the true
    // originating account on operations. This is important for liquidity operations, as these are permissioned
    // operations that can only be performed by the owner of the pool. Without this check, a malicious router
    // could spoof the address of the owner, allowing anyone to call permissioned functions.
    //
    // Since the initialization mechanism does not allow verification of the router, it is technically possible
    // to front-run `initialize`. This should not be a concern in the typical LBP use case of a new token launch,
    // where there is no existing liquidity. In the unlikely event it is a concern, `LBPoolFactory` provides the
    // `createAndInitialize` function, which does both operations in a single step.

    // solhint-disable-next-line var-name-mixedcase
    address private immutable _trustedRouter;

    PoolState private _poolState;

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

    /// @dev Indicates that the router that called the Vault is not trusted, so liquidity operations should revert.
    error RouterNotTrusted();

    /// @dev Indicates that the `owner` has disabled swaps.
    error SwapsDisabled();

    /// @dev Indicates that removing liquidity is not allowed.
    error RemovingLiquidityNotAllowed();

    /// @dev Indicates that swapping the bootstrap token is not allowed.
    error SwapOfBootstrapToken();

    /// @dev Indicates a wrongfully set bootstrap token.
    error InvalidBootstrapToken();

    constructor(
        NewPoolParams memory params,
        IVault vault,
        address owner,
        address trustedRouter,
        LBPParams memory lbpparams,
        TokenConfig[] memory tokenConfig
    ) WeightedPool(params, vault) Ownable(owner) {
        // WeightedPool validates `numTokens == normalizedWeights.length`, and ensures valid weights.
        // Here we additionally enforce that LBPs must be two-token pools.
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, params.numTokens);

        // Set the trusted router (passed down from the factory).
        _trustedRouter = trustedRouter;

        // Ensure startTime >= now.
        uint256 startTime = GradualValueChange.resolveStartTime(lbpparams.startTime, lbpparams.endTime);

        if (!_doesPoolContainBootstrapToken(lbpparams.bootstrapToken, tokenConfig)) {
            revert InvalidBootstrapToken();
        }

        bootstrapTokenIndex = _getBootstrapTokenIndex(lbpparams.bootstrapToken, tokenConfig);
        bootstrapToken = lbpparams.bootstrapToken;
        allowRemovalOnlyAfterWeightChange = lbpparams.allowRemovalOnlyAfterWeightChange;
        restrictSaleOfBootstrapToken = lbpparams.restrictSaleOfBootstrapToken;

        _startGradualWeightChange(
            startTime.toUint32(),
            lbpparams.endTime.toUint32(),
            params.normalizedWeights,
            lbpparams.endWeights
        );
    }

    /// @notice Returns the trusted router, which is the gateway to add liquidity to the pool.
    function getTrustedRouter() external view returns (address) {
        return _trustedRouter;
    }

    /**
     * @notice Return start time, end time, and endWeights as an array.
     * @dev Current weights should be retrieved via `getNormalizedWeights()`.
     * @return startTime The starting timestamp of any ongoing weight change
     * @return endTime The ending timestamp of any ongoing weight change
     * @return endWeights The "destination" weights, sorted in token registration order
     */
    function getGradualWeightUpdateParams()
        public
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

    function getTokenSwapEnabled(PoolSwapParams memory request) external view returns (bool) {
        return _getTokenSwapAllowed(request);
    }

    /*******************************************************************************
                                Permissioned Functions
    *******************************************************************************/

    /// @inheritdoc WeightedPool
    function onSwap(PoolSwapParams memory request) public view override onlyVault returns (uint256) {
        if (!_getPoolSwapEnabled()) {
            revert SwapsDisabled();
        }
        if (!_getTokenSwapAllowed(request)) {
            revert SwapOfBootstrapToken();
        }

        return super.onSwap(request);
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
        TokenConfig[] memory tokenConfig,
        LiquidityManagement calldata
    ) public view override onlyVault returns (bool) {
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, tokenConfig.length);

        return pool == address(this);
    }

    // Return HookFlags struct that indicates which hooks this contract supports
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        // Ensure the caller is the owner, as only the owner can add liquidity.
        hookFlags.shouldCallBeforeInitialize = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;
        hookFlags.shouldCallBeforeRemoveLiquidity = true;
    }

    function onBeforeInitialize(uint256[] memory, bytes memory) public view override onlyVault returns (bool success) {
        // We don't have the router argument here, but with only one trusted router this should be enough considering
        // `initialize` can only happen once.
        // If the sender is correct in the trusted router, either everything is fine, or the owner is doing something
        // else with the trusted router while at the same time giving away the execution to a frontrunner, which
        // is highly unlikely.
        // In any case, this is just an extra guardrail to start the pool with the correct proportions, and for that
        // the sender needs liquidity for the token being launched. For a token that is not fully public, the owner
        // should have the required liquidity, and frontrunning the pool initialization is no different from
        // just creating another pool.
        return IRouterCommon(_trustedRouter).getSender() == owner();
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
        if (router != _trustedRouter) {
            revert RouterNotTrusted();
        }
        return IRouterCommon(router).getSender() == owner();
    }

    /**
     * @notice Checks if a weight change is ongoing before allowing liquidity removal.
     * @dev If a weight change is ongoing, the function reverts with "removingLiquidityNotAllowed".
     * @param router The address of the router.
     */
    // this function should check if a weight change is ongoing. If it is ongoing, it should revert with "removingLiquidityNOtAllowed"
    function onBeforeRemoveLiquidity(
        address router,
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public view override onlyVault returns (bool success) {
        if (router != _trustedRouter) {
            revert RouterNotTrusted();
        }

        // Checks to see if removal of liquidity is only allowed after the weight change has ended.
        (, uint256 endTime, ) = getGradualWeightUpdateParams();
        if (allowRemovalOnlyAfterWeightChange && block.timestamp < endTime) {
            revert RemovingLiquidityNotAllowed();
        }

        return true;
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
        // Swaps are only enabled, once the weight change has started.
        (uint256 startTime, , ) = getGradualWeightUpdateParams();
        return block.timestamp >= startTime;
    }

    function _getTokenSwapAllowed(PoolSwapParams memory params) private view returns (bool) {
        if (restrictSaleOfBootstrapToken) {
            if (params.kind == SwapKind.EXACT_IN) {
                return params.indexIn == bootstrapTokenIndex ? false : true;
            } else {
                // exact out swap
                return params.indexOut == bootstrapTokenIndex ? false : true;
            }
        }
        return true;
    }

    function _doesPoolContainBootstrapToken(
        address token,
        TokenConfig[] memory tokenConfig
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < tokenConfig.length; i++) {
            if (address(tokenConfig[i].token) == token) {
                return true;
            }
        }
        return false;
    }

    function _getBootstrapTokenIndex(address token, TokenConfig[] memory tokenConfig) internal pure returns (uint256) {
        IERC20[] memory tokens = new IERC20[](tokenConfig.length);
        for (uint256 i = 0; i < tokenConfig.length; i++) {
            tokens[i] = tokenConfig[i].token;
        }
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(tokens);
        if (token < address(sortedTokens[1])) {
            return 0;
        } else {
            return 1;
        }
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
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, startWeights.length);
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, endWeights.length);

        if (endWeights[0] < _MIN_WEIGHT || endWeights[1] < _MIN_WEIGHT) {
            revert MinWeight();
        }
        if (endWeights[0] + endWeights[1] != FixedPoint.ONE) {
            revert NormalizedWeightInvariant();
        }

        PoolState memory poolState = _poolState;

        poolState.startTime = startTime;
        poolState.endTime = endTime;

        // These have been validated, but SafeCast anyway out of an abundance of caution.
        poolState.startWeight0 = startWeights[0].toUint64();
        poolState.endWeight0 = endWeights[0].toUint64();

        _poolState = poolState;

        emit GradualWeightUpdateScheduled(startTime, endTime, startWeights, endWeights);
    }
}
