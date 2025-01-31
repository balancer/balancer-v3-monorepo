// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    IWeightedPool,
    WeightedPoolDynamicData,
    WeightedPoolImmutableData
} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import {
    ILBPool,
    LBPoolImmutableData,
    LBPoolDynamicData,
    LBPParams
} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

import { GradualValueChange } from "../lib/GradualValueChange.sol";
import { WeightedPool } from "../WeightedPool.sol";

/**
 * @notice Weighted Pool with mutable weights, designed to support v3 Liquidity Bootstrapping.
 * @dev Inheriting from WeightedPool is only slightly wasteful (setting 2 immutable weights and `_totalTokens`,
 * which will not be used later), and it is tremendously helpful for pool validation and any potential future
 * base contract changes.
 */
contract LBPool is ILBPool, WeightedPool, Ownable2Step, BaseHooks {
    // The sale parameters are timestamp-based: they should not be relied upon for sub-minute accuracy.
    // solhint-disable not-rely-on-time

    // LBPs are constrained to two tokens: project and reserve.
    uint256 private constant _TWO_TOKENS = 2;

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

    // The project token is the one being launched; the reserve token is the token used to buy them (usually
    // a stablecoin or WETH).
    IERC20 private immutable _projectToken;
    IERC20 private immutable _reserveToken;

    uint256 private immutable _projectTokenIndex;
    uint256 private immutable _reserveTokenIndex;

    uint256 private immutable _startTime;
    uint256 private immutable _endTime;

    uint256 private immutable _projectTokenStartWeight;
    uint256 private immutable _reserveTokenStartWeight;
    uint256 private immutable _projectTokenEndWeight;
    uint256 private immutable _reserveTokenEndWeight;

    // If false, project tokens can only be bought, not sold back into the pool.
    bool private immutable _enableProjectTokenSwapsIn;

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

    /// @dev Function is inherited but not implemented.
    error NotImplemented();

    constructor(
        string memory name,
        string memory symbol,
        LBPParams memory lbpParams,
        IVault vault,
        address trustedRouter,
        string memory version
    ) WeightedPool(_buildWeightedPoolParams(name, symbol, version, lbpParams), vault) Ownable(lbpParams.owner) {
        // WeightedPool has already validated the starting weights; we still need to validate the ending weights.
        if (lbpParams.projectTokenEndWeight < _MIN_WEIGHT || lbpParams.reserveTokenEndWeight < _MIN_WEIGHT) {
            revert IWeightedPool.MinWeight();
        }

        if (lbpParams.projectTokenEndWeight + lbpParams.reserveTokenEndWeight != FixedPoint.ONE) {
            revert IWeightedPool.NormalizedWeightInvariant();
        }

        // Set the trusted router (passed down from the factory), and the rest of the immutable variables.
        _trustedRouter = trustedRouter;

        _projectToken = lbpParams.projectToken;
        _reserveToken = lbpParams.reserveToken;

        _enableProjectTokenSwapsIn = lbpParams.enableProjectTokenSwapsIn;

        _startTime = GradualValueChange.resolveStartTime(lbpParams.startTime, lbpParams.endTime);
        _endTime = lbpParams.endTime;

        _projectTokenStartWeight = lbpParams.projectTokenStartWeight;
        _reserveTokenStartWeight = lbpParams.reserveTokenStartWeight;

        _projectTokenEndWeight = lbpParams.projectTokenEndWeight;
        _reserveTokenEndWeight = lbpParams.reserveTokenEndWeight;

        (_projectTokenIndex, _reserveTokenIndex) = lbpParams.projectToken < lbpParams.reserveToken ? (0, 1) : (1, 0);

        // Preserve event compatibility with previous LBP versions.
        uint256[] memory startWeights = new uint256[](_TWO_TOKENS);
        uint256[] memory endWeights = new uint256[](_TWO_TOKENS);
        (startWeights[_projectTokenIndex], startWeights[_reserveTokenIndex]) = (
            lbpParams.projectTokenStartWeight,
            lbpParams.reserveTokenStartWeight
        );
        (endWeights[_projectTokenIndex], endWeights[_reserveTokenIndex]) = (
            lbpParams.projectTokenEndWeight,
            lbpParams.reserveTokenEndWeight
        );

        emit GradualWeightUpdateScheduled(lbpParams.startTime, lbpParams.endTime, startWeights, endWeights);
    }

    /**
     * @notice Returns the trusted router, which is the gateway to add liquidity to the pool.
     * @return trustedRouter Address of the trusted router (i.e., one that reliably reports the sender)
     */
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

        startWeights = new uint256[](_TWO_TOKENS);
        (startWeights[_projectTokenIndex], startWeights[_reserveTokenIndex]) = (
            _projectTokenStartWeight,
            _reserveTokenStartWeight
        );

        endWeights = new uint256[](_TWO_TOKENS);
        (endWeights[_projectTokenIndex], endWeights[_reserveTokenIndex]) = (
            _projectTokenEndWeight,
            _reserveTokenEndWeight
        );
    }

    /**
     * @notice Indicate whether or not swaps are enabled for this pool.
     * @dev For LBPs, swaps are enabled during the token sale, between the start and end times. Note that this does
     * not check whether the pool or Vault is paused, which can only happen through governance action. This can be
     * checked using `getPoolConfig` on the Vault, or by calling `getLBPoolDynamicData` here.
     *
     * @return swapEnabled True if the sale is in progress
     */
    function isSwapEnabled() external view returns (bool) {
        return _isSwapEnabled();
    }

    function _isSwapEnabled() internal view returns (bool) {
        return block.timestamp >= _startTime && block.timestamp <= _endTime;
    }

    /**
     * @notice Indicate whether project tokens can be sold back into the pool.
     * @dev Note that theoretically, anyone holding project tokens could create a new pool alongside the LBP that did
     * allow "selling" project tokens. This restriction only applies to the primary LBP.
     *
     * @return projectTokenSwapInEnabled True if acquired project tokens can be traded for the reserve in this pool
     */
    function isProjectTokenSwapInEnabled() external view returns (bool) {
        return _enableProjectTokenSwapsIn;
    }

    /**
     * @notice Not implemented; reverts unconditionally.
     * @dev This is because the LBP dynamic data also includes the weights, so overriding this would be incomplete
     * and potentially misleading.
     */
    function getWeightedPoolDynamicData() external pure override returns (WeightedPoolDynamicData memory) {
        revert NotImplemented();
    }

    /**
     * @notice Not implemented; reverts unconditionally.
     * @dev This is because in the standard Weighted Pool, weights are included in the immutable data. In the LBP,
     * weights can change, so they are instead part of the dynamic data.
     */
    function getWeightedPoolImmutableData() external pure override returns (WeightedPoolImmutableData memory) {
        revert NotImplemented();
    }

    /// @inheritdoc ILBPool
    function getLBPoolDynamicData() external view override returns (LBPoolDynamicData memory data) {
        data.balancesLiveScaled18 = _vault.getCurrentLiveBalances(address(this));
        data.normalizedWeights = _getNormalizedWeights();
        data.staticSwapFeePercentage = _vault.getStaticSwapFeePercentage((address(this)));
        data.totalSupply = totalSupply();

        PoolConfig memory poolConfig = _vault.getPoolConfig(address(this));
        data.isPoolInitialized = poolConfig.isPoolInitialized;
        data.isPoolPaused = poolConfig.isPoolPaused;
        data.isPoolInRecoveryMode = poolConfig.isPoolInRecoveryMode;
        data.isSwapEnabled = _isSwapEnabled();
    }

    /// @inheritdoc ILBPool
    function getLBPoolImmutableData() external view override returns (LBPoolImmutableData memory data) {
        data.tokens = _vault.getPoolTokens(address(this));
        (data.decimalScalingFactors, ) = _vault.getPoolTokenRates(address(this));
        data.isProjectTokenSwapInEnabled = _enableProjectTokenSwapsIn;
        data.startTime = _startTime;
        data.endTime = _endTime;

        data.startWeights = new uint256[](_TWO_TOKENS);
        data.startWeights[_projectTokenIndex] = _projectTokenStartWeight;
        data.startWeights[_reserveTokenIndex] = _reserveTokenStartWeight;

        data.endWeights = new uint256[](_TWO_TOKENS);
        data.endWeights[_projectTokenIndex] = _projectTokenEndWeight;
        data.endWeights[_reserveTokenIndex] = _reserveTokenEndWeight;
    }

    /*******************************************************************************
                                    Base Pool Hooks
    *******************************************************************************/

    /// @inheritdoc WeightedPool
    function onSwap(
        PoolSwapParams memory request
    ) public view override(IBasePool, WeightedPool) onlyVault returns (uint256) {
        if (_isSwapEnabled() == false) {
            revert SwapsDisabled();
        }

        // If project token swaps are not enabled, project token must be the token out.
        if (_enableProjectTokenSwapsIn == false && request.indexOut != _projectTokenIndex) {
            revert SwapOfProjectTokenIn();
        }

        return super.onSwap(request);
    }

    /*******************************************************************************
                                      Pool Hooks
    *******************************************************************************/

    /**
     * @notice Hook to be executed when the pool is registered.
     * @dev Returns true if registration was successful; false will revert with `HookRegistrationFailed`.
     * @param pool Address of the pool (must be this contract for LBPs: the pool is also the hook)
     * @param tokenConfig The token configuration of the pool being registered (e.g., type)
     * @return success True if the hook allowed the registration, false otherwise
     */
    function onRegister(
        address,
        address pool,
        TokenConfig[] memory tokenConfig,
        LiquidityManagement calldata
    ) public view override onlyVault returns (bool) {
        // These preconditions are guaranteed by the standard LBPoolFactory, but check anyway.
        InputHelpers.ensureInputLengthMatch(_TWO_TOKENS, tokenConfig.length);

        // Ensure there are no "WITH_RATE" tokens. We don't need to check anything else, as the Vault has already
        // ensured we don't have a STANDARD token with a rate provider.
        if (tokenConfig[0].tokenType != TokenType.STANDARD || tokenConfig[1].tokenType != TokenType.STANDARD) {
            revert IVaultErrors.InvalidTokenConfiguration();
        }

        return pool == address(this);
    }

    /**
     * @notice Return the HookFlags struct, which indicates which hooks this contract supports.
     * @dev For each flag set to true, the Vault will call the corresponding hook.
     * @return hookFlags Flags indicating which hooks are supported for LBPs
     */
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallBeforeInitialize = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;
        hookFlags.shouldCallBeforeRemoveLiquidity = true;
    }

    /**
     * @notice Block initialization if the sender is not the owner of the LBP.
     * @dev We don't have the router argument here, but with only one trusted router this should be enough considering
     * `initialize` can only happen once.
     *
     * If the sender is correct in the trusted router, either everything is fine, or the owner is doing something else
     * with the trusted router while at the same time giving away the execution to a frontrunner, which is highly
     * unlikely.
     *
     * In any case, this is just an extra guardrail to start the pool with the correct proportions, and for that the
     * sender needs liquidity for the token being launched. For a token that is not fully public, the owner should have
     * the required liquidity, and frontrunning the pool initialization is no different from just creating another
     * pool.
     *
     * The start time must be set far enough in the future to allow the initialization / initial funding to occur.
     * Otherwise, the sale will proceed with whatever liquidity is present at the start (possibly none), and any
     * liquidity added cannot be withdrawn until after the end time (unless the pool is placed in Recovery Mode).
     *
     * @return success If true, the sender matches (so the Vault will allow the initialization to proceed)
     */
    function onBeforeInitialize(uint256[] memory, bytes memory) public view override onlyVault returns (bool) {
        // Only allow initialization up to the start time.
        if (block.timestamp >= _startTime) {
            revert AddingLiquidityNotAllowed();
        }

        return IRouterCommon(_trustedRouter).getSender() == owner();
    }

    /// @notice Revert unconditionally; we require all liquidity to be added on initialization.
    function onBeforeAddLiquidity(
        address,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) public view override onlyVault returns (bool) {
        revert AddingLiquidityNotAllowed();
    }

    /**
     * @notice Only allow requests after the weight update is finished, and the sale is complete.
     * @return success Always true; if removing liquidity is not allowed, revert here with a more specific error
     */
    function onBeforeRemoveLiquidity(
        address,
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public view override onlyVault returns (bool) {
        // Only allow removing liquidity after end time.
        if (block.timestamp <= _endTime) {
            revert RemovingLiquidityNotAllowed();
        }

        return true;
    }

    /*******************************************************************************
                                  Internal Functions
    *******************************************************************************/

    function _getNormalizedWeight(uint256 tokenIndex) internal view override returns (uint256) {
        if (tokenIndex < _TWO_TOKENS) {
            return _getNormalizedWeights()[tokenIndex];
        }

        revert IVaultErrors.InvalidToken();
    }

    function _getNormalizedWeights() internal view override returns (uint256[] memory) {
        uint256[] memory normalizedWeights = new uint256[](_TWO_TOKENS);
        normalizedWeights[_projectTokenIndex] = _getProjectTokenNormalizedWeight();
        normalizedWeights[_reserveTokenIndex] = FixedPoint.ONE - normalizedWeights[_projectTokenIndex];

        return normalizedWeights;
    }

    function _getProjectTokenNormalizedWeight() internal view returns (uint256) {
        uint256 pctProgress = GradualValueChange.calculateValueChangeProgress(_startTime, _endTime);

        return GradualValueChange.interpolateValue(_projectTokenStartWeight, _projectTokenEndWeight, pctProgress);
    }

    function _buildWeightedPoolParams(
        string memory name,
        string memory symbol,
        string memory version,
        LBPParams memory lbpParams
    ) private pure returns (NewPoolParams memory) {
        (uint256 projectTokenIndex, uint256 reserveTokenIndex) = lbpParams.projectToken < lbpParams.reserveToken
            ? (0, 1)
            : (1, 0);

        uint256[] memory normalizedWeights = new uint256[](_TWO_TOKENS);
        normalizedWeights[projectTokenIndex] = lbpParams.projectTokenStartWeight;
        normalizedWeights[reserveTokenIndex] = lbpParams.reserveTokenStartWeight;

        // The WeightedPool will validate the starting weights (i.e., ensure they respect the minimum and sum to ONE).
        return
            NewPoolParams({
                name: name,
                symbol: symbol,
                numTokens: _TWO_TOKENS,
                normalizedWeights: normalizedWeights,
                version: version
            });
    }
}
