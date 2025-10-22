// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    IFixedPriceLBPool,
    FixedPriceLBPoolImmutableData,
    FixedPriceLBPoolDynamicData,
    FixedPriceLBPParams
} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IFixedPriceLBPool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { PoolInfo } from "@balancer-labs/v3-pool-utils/contracts/PoolInfo.sol";

import { GradualValueChange } from "../lib/GradualValueChange.sol";

/**
 * @notice Weighted Pool with mutable weights, designed to support v3 Liquidity Bootstrapping.
 * @dev Inheriting from WeightedPool is only slightly wasteful (setting 2 immutable weights and `_totalTokens`,
 * which will not be used later), and it is tremendously helpful for pool validation and any potential future
 * base contract changes.
 */
contract FixedPriceLBPool is IFixedPriceLBPool, Ownable2Step, BaseHooks, BalancerPoolToken, PoolInfo, Version {
    using FixedPoint for uint256;

    // The sale parameters are timestamp-based: they should not be relied upon for sub-minute accuracy.
    // solhint-disable not-rely-on-time

    // LBPs are constrained to two tokens: project and reserve.
    uint256 private constant _TWO_TOKENS = 2;

    // Fees are 18-decimal, floating point values, which will be stored in the Vault using 24 bits.
    // This means they have 0.00001% resolution (i.e., any non-zero bits < 1e11 will cause precision loss).
    // Minimum values help make the math well-behaved (i.e., the swap fee should overwhelm any rounding error).
    // Maximum values protect users by preventing permissioned actors from setting excessively high swap fees.
    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 0.001e16; // 0.001%
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 20e16; // 20%

    // LBPools are deployed with the Balancer standard router address, which we know reliably reports the true sender.
    address private immutable _trustedRouter;

    // The project token is the one being launched; the reserve token is the token used to buy them (usually
    // a stablecoin or WETH).
    IERC20 private immutable _projectToken;
    IERC20 private immutable _reserveToken;

    uint256 private immutable _projectTokenIndex;
    uint256 private immutable _reserveTokenIndex;

    uint256 private immutable _startTime;
    uint256 private immutable _endTime;

    // If true, project tokens can only be bought, not sold back to the pool (i.e., they cannot be the `tokenIn`
    // of a swap)
    bool private immutable _blockProjectTokenSwapsIn;

    uint256 private immutable _projectTokenRate;

    /// @notice Swaps are disabled except during the sale (i.e., between and start and end times).
    error SwapsDisabled();

    /// @notice Removing liquidity is not allowed before the end of the sale.
    error RemovingLiquidityNotAllowed();

    /// @notice The pool does not allow adding liquidity except during initialization and before the weight update.
    error AddingLiquidityNotAllowed();

    /// @notice THe LBP configuration prohibits selling the project token back into the pool.
    error SwapOfProjectTokenIn();

    /// @notice This overridden function is not implemented / required for the pool to work.
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
        FixedPriceLBPParams memory lbpParams,
        IVault vault,
        address trustedRouter,
        string memory version
    ) BalancerPoolToken(vault, name, symbol) PoolInfo(vault) Version(version) Ownable(lbpParams.owner) {
        // Checks that `endTime` is after `startTime`. If `startTime` is in the past, override it with the current
        // block time for consistency.
        _startTime = GradualValueChange.resolveStartTime(lbpParams.startTime, lbpParams.endTime);
        _endTime = lbpParams.endTime;

        // Set the trusted router (passed down from the factory), and the rest of the immutable variables.
        _trustedRouter = trustedRouter;

        _projectToken = lbpParams.projectToken;
        _reserveToken = lbpParams.reserveToken;

        _blockProjectTokenSwapsIn = lbpParams.blockProjectTokenSwapsIn;

        _projectTokenRate = lbpParams.projectTokenRate;

        (_projectTokenIndex, _reserveTokenIndex) = lbpParams.projectToken < lbpParams.reserveToken ? (0, 1) : (1, 0);
    }

    /**
     * @notice Returns the trusted router, which is used to initialize and seed the pool.
     * @return trustedRouter Address of the trusted router (i.e., one that reliably reports the sender)
     */
    function getTrustedRouter() external view returns (address) {
        return _trustedRouter;
    }

    /// @inheritdoc IFixedPriceLBPool
    function getProjectToken() external view returns (IERC20) {
        return _projectToken;
    }

    /// @inheritdoc IFixedPriceLBPool
    function getReserveToken() external view returns (IERC20) {
        return _reserveToken;
    }

    /// @inheritdoc IFixedPriceLBPool
    function getProjectTokenRate() external view returns (uint256) {
        return _projectTokenRate;
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
        data.isProjectTokenSwapInBlocked = _blockProjectTokenSwapsIn;
        data.startTime = _startTime;
        data.endTime = _endTime;
    }

    /*******************************************************************************
                                    Base Pool Hooks
    *******************************************************************************/

    /// @inheritdoc IBasePool
    function onSwap(PoolSwapParams memory request) public view returns (uint256 amountCalculatedScaled18) {
        // Block if the sale has not started or has ended.
        if (_isSwapEnabled() == false) {
            revert SwapsDisabled();
        }

        // If project token swaps are blocked, project token must be the token out.
        if (_blockProjectTokenSwapsIn && request.indexOut != _projectTokenIndex) {
            revert SwapOfProjectTokenIn();
        }

        if (request.kind == SwapKind.EXACT_IN) {
            // Calculated amount is amount out; round down.
            if (request.indexIn == _reserveTokenIndex) {
                amountCalculatedScaled18 = request.amountGivenScaled18.divDown(_projectTokenRate);
            } else {
                amountCalculatedScaled18 = request.amountGivenScaled18.mulDown(_projectTokenRate);
            }
        } else {
            // Calculated amount is amount in; round up.
            if (request.indexIn == _reserveTokenIndex) {
                amountCalculatedScaled18 = request.amountGivenScaled18.divUp(_projectTokenRate);
            } else {
                amountCalculatedScaled18 = request.amountGivenScaled18.mulUp(_projectTokenRate);
            }
        }

        return amountCalculatedScaled18;
    }

    function computeInvariant(uint256[] memory balances, Rounding) public view returns (uint256) {
        // inv = x + y
        return balances[_projectTokenIndex].mulDown(_projectTokenRate) + balances[_reserveTokenIndex];
    }

    /// @inheritdoc IBasePool
    function computeBalance(uint256[] memory, uint256, uint256) external pure returns (uint256) {
        revert NotImplemented();
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMinimumSwapFeePercentage() external pure returns (uint256) {
        return _MIN_SWAP_FEE_PERCENTAGE;
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMaximumSwapFeePercentage() external pure returns (uint256) {
        return _MAX_SWAP_FEE_PERCENTAGE;
    }

    /// @inheritdoc IUnbalancedLiquidityInvariantRatioBounds
    function getMinimumInvariantRatio() external pure returns (uint256) {
        revert NotImplemented();
    }

    /// @inheritdoc IUnbalancedLiquidityInvariantRatioBounds
    function getMaximumInvariantRatio() external pure returns (uint256) {
        revert NotImplemented();
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
    ) public view override returns (bool) {
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
    function onBeforeInitialize(uint256[] memory, bytes memory) public view override onlyBeforeSale returns (bool) {
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
    ) public view override onlyBeforeSale returns (bool) {
        return router == _trustedRouter && ISenderGuard(router).getSender() == owner();
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
    ) public view virtual override returns (bool) {
        // Only allow removing liquidity after end time.
        if (block.timestamp <= _endTime) {
            revert RemovingLiquidityNotAllowed();
        }

        return true;
    }
}
