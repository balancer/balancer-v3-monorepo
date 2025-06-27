// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
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
import { LBPoolLib } from "../lib/LBPoolLib.sol";

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

    // LBPools are deployed with the Balancer standard router address, which we know reliably reports the true sender.
    address private immutable _trustedRouter;
    address private immutable _migrationRouter;

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

    uint256 private immutable _lockDurationAfterMigration;
    uint256 private immutable _bptPercentageToMigrate;
    uint256 private immutable _migrationWeightProjectToken;
    uint256 private immutable _migrationWeightReserveToken;

    // If true, project tokens can only be bought, not sold back to the pool (i.e., they cannot be the `tokenIn`
    // of a swap)
    bool private immutable _blockProjectTokenSwapsIn;

    /**
     * @notice Emitted on deployment to record the sale parameters.
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

    /// @notice Swaps are disabled except during the sale (i.e., between and start and end times).
    error SwapsDisabled();

    /// @notice Removing liquidity is not allowed before the end of the sale.
    error RemovingLiquidityNotAllowed();

    /// @notice The pool does not allow adding liquidity except during initialization and before the weight update.
    error AddingLiquidityNotAllowed();

    /// @notice THe LBP configuration prohibits selling the project token back into the pool.
    error SwapOfProjectTokenIn();

    /// @notice LBPs are WeightedPools by inheritance, but WeightedPool immutable/dynamic getters are wrong for LBPs.
    error NotImplemented();

    /// @notice Only allow adding liquidity (including initialization) before the sale.
    modifier onlyBeforeSale() {
        if (block.timestamp >= _startTime) {
            revert AddingLiquidityNotAllowed();
        }
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        LBPParams memory lbpParams,
        IVault vault,
        address trustedRouter,
        address migrationRouter,
        string memory version,
        uint256 lockDurationAfterMigration,
        uint256 bptPercentageToMigrate,
        uint256 migrationWeightProjectToken,
        uint256 migrationWeightReserveToken
    ) WeightedPool(_buildWeightedPoolParams(name, symbol, version, lbpParams), vault) Ownable(lbpParams.owner) {
        // Checks that the weights are valid and `endTime` is after `startTime`. If `startTime` is in the past,
        // avoid abrupt weight changes by overriding it with the current block time.
        _startTime = LBPoolLib.verifyWeightUpdateParameters(
            lbpParams.startTime,
            lbpParams.endTime,
            lbpParams.projectTokenStartWeight,
            lbpParams.reserveTokenStartWeight,
            lbpParams.projectTokenEndWeight,
            lbpParams.reserveTokenEndWeight
        );
        _endTime = lbpParams.endTime;

        // Set the trusted router (passed down from the factory), and the rest of the immutable variables.
        _trustedRouter = trustedRouter;
        _migrationRouter = migrationRouter;

        _projectToken = lbpParams.projectToken;
        _reserveToken = lbpParams.reserveToken;

        _blockProjectTokenSwapsIn = lbpParams.blockProjectTokenSwapsIn;

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

        _lockDurationAfterMigration = lockDurationAfterMigration;
        _bptPercentageToMigrate = bptPercentageToMigrate;
        _migrationWeightProjectToken = migrationWeightProjectToken;
        _migrationWeightReserveToken = migrationWeightReserveToken;

        emit GradualWeightUpdateScheduled(_startTime, _endTime, startWeights, endWeights);
    }

    /**
     * @notice Returns the trusted router, which is used to initialize and seed the pool.
     * @return trustedRouter Address of the trusted router (i.e., one that reliably reports the sender)
     */
    function getTrustedRouter() external view returns (address) {
        return _trustedRouter;
    }

    /// @inheritdoc ILBPool
    function getProjectToken() external view returns (IERC20) {
        return _projectToken;
    }

    /// @inheritdoc ILBPool
    function getReserveToken() external view returns (IERC20) {
        return _reserveToken;
    }

    /**
     * @notice Return start time and end time, as well as starting and ending weights as arrays.
     * @dev The current weights should be retrieved via `getNormalizedWeights()`.
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
     * @return isProjectTokenSwapInBlocked If true, acquired project tokens cannot be traded for reserve in this pool
     */
    function isProjectTokenSwapInBlocked() external view returns (bool) {
        return _blockProjectTokenSwapsIn;
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
        data.projectTokenIndex = _projectTokenIndex;
        data.reserveTokenIndex = _reserveTokenIndex;

        (data.decimalScalingFactors, ) = _vault.getPoolTokenRates(address(this));
        data.isProjectTokenSwapInBlocked = _blockProjectTokenSwapsIn;
        data.startTime = _startTime;
        data.endTime = _endTime;

        data.startWeights = new uint256[](_TWO_TOKENS);
        data.startWeights[_projectTokenIndex] = _projectTokenStartWeight;
        data.startWeights[_reserveTokenIndex] = _reserveTokenStartWeight;

        data.endWeights = new uint256[](_TWO_TOKENS);
        data.endWeights[_projectTokenIndex] = _projectTokenEndWeight;
        data.endWeights[_reserveTokenIndex] = _reserveTokenEndWeight;

        // Migration-related params, non-zero if the pool supports migration.
        data.migrationRouter = _migrationRouter;
        data.bptLockDuration = _lockDurationAfterMigration;
        data.bptPercentageToMigrate = _bptPercentageToMigrate;
        data.migrationWeightProjectToken = _migrationWeightProjectToken;
        data.migrationWeightReserveToken = _migrationWeightReserveToken;
    }

    /*******************************************************************************
                                    Base Pool Hooks
    *******************************************************************************/

    /// @inheritdoc WeightedPool
    function onSwap(
        PoolSwapParams memory request
    ) public view override(IBasePool, WeightedPool) onlyVault returns (uint256) {
        // Block if the sale has not started or has ended.
        if (_isSwapEnabled() == false) {
            revert SwapsDisabled();
        }

        // If project token swaps are blocked, project token must be the token out.
        if (_blockProjectTokenSwapsIn && request.indexOut != _projectTokenIndex) {
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
        // Required to enforce single-LP liquidity provision, and ensure all funding occurs before the sale.
        hookFlags.shouldCallBeforeInitialize = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;

        // Required to enforce the liquidity can only be withdrawn after the end of the sale.
        hookFlags.shouldCallBeforeRemoveLiquidity = true;
    }

    /**
     * @notice Block initialization if the sale has already started.
     * @dev Take care to set the start time far enough in advance to allow for funding; otherwise the pool will remain
     * unfunded and need to be redeployed. Note that initialization does not pass the router address, so we cannot
     * directly check that here, though there has to be a call on the trusted router for its `getSender` to be
     * non-zero.
     *
     * @return success Always true: allow the initialization to proceed if the time condition has been met
     */
    function onBeforeInitialize(
        uint256[] memory,
        bytes memory
    ) public view override onlyVault onlyBeforeSale returns (bool) {
        return ISenderGuard(_trustedRouter).getSender() == owner();
    }

    /**
     * @notice Allow the owner to add liquidity before the start of the sale.
     * @param router The router used for the operation
     * @return success True (allowing the operation to proceed) if the owner is calling through the trusted router
     */
    function onBeforeAddLiquidity(
        address router,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) public view override onlyVault onlyBeforeSale returns (bool) {
        return router == _trustedRouter && ISenderGuard(router).getSender() == owner();
    }

    /**
     * @notice Only allow requests after the weight update is finished, and the sale is complete.
     * @return success Always true; if removing liquidity is not allowed, revert here with a more specific error
     */
    function onBeforeRemoveLiquidity(
        address router,
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public view virtual override onlyVault returns (bool) {
        // Only allow removing liquidity after end time.
        if (block.timestamp <= _endTime) {
            revert RemovingLiquidityNotAllowed();
        }

        return _migrationRouter == address(0) || router == _migrationRouter;
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

    // Build the required struct for initializing the underlying WeightedPool. Called on construction.
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
