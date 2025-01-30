// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {
    ILBPool,
    LBPoolImmutableData,
    LBPoolDynamicData
} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import {
    WeightedPoolDynamicData,
    WeightedPoolImmutableData
} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
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
import { LBPoolLib } from "../lib/LBPoolLib.sol";

/**
 * @notice Weighted Pool with mutable weights, designed to support v3 Liquidity Bootstrapping.
 * @dev Inheriting from WeightedPool is only slightly wasteful (setting 2 immutable weights and `_totalTokens`,
 * which will not be used later), and it is tremendously helpful for pool validation and any potential future
 * base contract changes.
 */
contract LBPool is ILBPool, WeightedPool, Ownable2Step, BaseHooks {
    using SafeCast for *;

    struct LBPParams {
        address owner;
        uint256 startTime;
        uint256 endTime;
        uint256[] startWeights;
        uint256[] endWeights;
        IERC20 projectToken;
        bool enableProjectTokenSwapsIn;
    }

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

    IERC20 private immutable _projectToken;
    IERC20 private immutable _reserveToken;

    bool private immutable _enableProjectTokenSwapsIn;

    uint256 private immutable _projectTokenIndex;

    uint256 private immutable _startTime;
    uint256 private immutable _endTime;
    uint256 private immutable _startWeight0;
    uint256 private immutable _startWeight1;
    uint256 private immutable _endWeight0;
    uint256 private immutable _endWeight1;

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

    /// @dev The pool does not allow adding liquidity while the token weights are being updated.
    error AddingLiquidityNotAllowed();

    /// @dev Indicates that swapping the project token is not allowed.
    error SwapOfProjectTokenIn();

    /// @dev Indicates a wrongfully set project token.
    error InvalidProjectToken(IERC20 projectToken);

    /// @dev Function is inherited but not implemented.
    error NotImplemented();

    constructor(
        NewPoolParams memory params,
        IVault vault,
        address trustedRouter,
        LBPParams memory lbpParams,
        TokenConfig[] memory tokenConfig
    ) WeightedPool(params, vault) Ownable(lbpParams.owner) {
        // WeightedPool validates `numTokens == normalizedWeights.length`, and ensures valid weights.
        // Here we additionally enforce that LBPs must be two-token pools.
        InputHelpers.ensureInputLengthMatch(LBPoolLib.NUM_TOKENS, params.numTokens);

        // Set the trusted router (passed down from the factory).
        _trustedRouter = trustedRouter;

        if (lbpParams.projectToken == tokenConfig[0].token) {
            _projectTokenIndex = 0;
            _projectToken = tokenConfig[0].token;
            _reserveToken = tokenConfig[1].token;
        } else if (lbpParams.projectToken == tokenConfig[1].token) {
            _projectTokenIndex = 1;
            _projectToken = tokenConfig[1].token;
            _reserveToken = tokenConfig[0].token;
        } else {
            revert InvalidProjectToken(lbpParams.projectToken);
        }

        _enableProjectTokenSwapsIn = lbpParams.enableProjectTokenSwapsIn;

        // Ensure weight normalization, and endTime > startTime.
        uint256 startTime = LBPoolLib.verifyWeightUpdateParameters(
            lbpParams.startTime,
            lbpParams.endTime,
            lbpParams.startWeights,
            lbpParams.endWeights
        );

        _startTime = startTime;
        _endTime = lbpParams.endTime;

        _startWeight0 = lbpParams.startWeights[0];
        _startWeight1 = lbpParams.startWeights[1];

        _endWeight0 = lbpParams.endWeights[0];
        _endWeight1 = lbpParams.endWeights[1];

        emit GradualWeightUpdateScheduled(startTime, lbpParams.endTime, lbpParams.startWeights, lbpParams.endWeights);
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
     * @return startWeights The "initial" weights, sorted in token registration order
     * @return endWeights The "destination" weights, sorted in token registration order
     */
    function getGradualWeightUpdateParams()
        public
        view
        returns (uint256 startTime, uint256 endTime, uint256[] memory startWeights, uint256[] memory endWeights)
    {
        startTime = _startTime;
        endTime = _endTime;

        startWeights = new uint256[](LBPoolLib.NUM_TOKENS);
        startWeights[0] = _startWeight0;
        startWeights[1] = _startWeight1;

        endWeights = new uint256[](LBPoolLib.NUM_TOKENS);
        endWeights[0] = _endWeight0;
        endWeights[1] = _endWeight1;
    }

    /**
     * @notice Indicate whether swaps are enabled or not for the given pool.
     * @return swapEnabled True if trading is enabled
     */
    function isSwapEnabled() external view returns (bool) {
        return _isSwapEnabled();
    }

    function isProjectTokenSwapInEnabled() external view returns (bool) {
        return _enableProjectTokenSwapsIn;
    }

    /*******************************************************************************
                                Permissioned Functions
    *******************************************************************************/

    /// @inheritdoc WeightedPool
    function onSwap(
        PoolSwapParams memory request
    ) public view override(IBasePool, WeightedPool) onlyVault returns (uint256) {
        if (_isSwapEnabled() == false) {
            revert SwapsDisabled();
        }
        if (_isSwapRequestAllowed(request) == false) {
            revert SwapOfProjectTokenIn();
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
        InputHelpers.ensureInputLengthMatch(LBPoolLib.NUM_TOKENS, tokenConfig.length);

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
     * @notice Check that the caller who initiated the add liquidity operation is the owner, and only allows
     * operations before `startTime`.
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

        // Only allow adding liquidity up to start time.
        if (block.timestamp > _startTime) {
            revert AddingLiquidityNotAllowed();
        }

        return IRouterCommon(router).getSender() == owner();
    }

    /// @notice Only allows requests after the weight update is finished.
    function onBeforeRemoveLiquidity(
        address,
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public view override onlyVault returns (bool success) {
        // Only allow removing liquidity after end time.
        if (block.timestamp < _endTime) {
            revert RemovingLiquidityNotAllowed();
        }

        return true;
    }

    /// @notice Not implemented; reverts unconditionally.
    function getWeightedPoolDynamicData() external pure override returns (WeightedPoolDynamicData memory) {
        revert NotImplemented();
    }

    /// @notice Not implemented; reverts unconditionally.
    function getWeightedPoolImmutableData() external pure override returns (WeightedPoolImmutableData memory) {
        revert NotImplemented();
    }

    /*******************************************************************************
                                  Internal Functions
    *******************************************************************************/

    function _getNormalizedWeight(uint256 tokenIndex) internal view virtual override returns (uint256) {
        if (tokenIndex < LBPoolLib.NUM_TOKENS) {
            return _getNormalizedWeights()[tokenIndex];
        }

        revert IVaultErrors.InvalidToken();
    }

    function _getNormalizedWeights() internal view override returns (uint256[] memory) {
        uint256[] memory normalizedWeights = new uint256[](LBPoolLib.NUM_TOKENS);
        normalizedWeights[0] = _getNormalizedWeight0();
        normalizedWeights[1] = FixedPoint.ONE - normalizedWeights[0];

        return normalizedWeights;
    }

    function _getNormalizedWeight0() internal view virtual returns (uint256) {
        uint256 pctProgress = GradualValueChange.calculateValueChangeProgress(_startTime, _endTime);

        return GradualValueChange.interpolateValue(_startWeight0, _endWeight0, pctProgress);
    }

    function _isSwapEnabled() private view returns (bool) {
        // Swaps are only enabled while the weight is changing.
        return block.timestamp >= _startTime && block.timestamp <= _endTime;
    }

    function _isSwapRequestAllowed(PoolSwapParams memory params) private view returns (bool) {
        // If project token swaps are enabled, the request is always valid.
        // If not, project token must be the token out.
        return _enableProjectTokenSwapsIn || params.indexOut == _projectTokenIndex;
    }

    function getLBPoolDynamicData() external view override returns (LBPoolDynamicData memory data) {}

    function getLBPoolImmutableData() external view override returns (LBPoolImmutableData memory data) {}
}
