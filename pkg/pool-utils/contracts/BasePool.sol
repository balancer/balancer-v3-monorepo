// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { ERC20PoolToken } from "@balancer-labs/v3-solidity-utils/contracts/token/ERC20PoolToken.sol";
import { TemporarilyPausable } from "@balancer-labs/v3-solidity-utils/contracts/helpers/TemporarilyPausable.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

/// @notice Reference implementation for the base layer of a Pool contract.
abstract contract BasePool is IBasePool, ERC20PoolToken, TemporarilyPausable {
    using FixedPoint for uint256;
    using ScalingHelpers for *;

    IVault internal immutable _vault;

    // TODO: move this to Vault.
    uint256 private constant _MIN_TOKENS = 2;

    uint256 private constant _DEFAULT_MINIMUM_BPT = 1e6;
    uint256 private constant _SWAP_FEE_PERCENTAGE = 0;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) ERC20PoolToken(vault, name, symbol) TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration) {
        _vault = vault;
        if (tokens.length < _MIN_TOKENS) {
            revert MinTokens();
        }
        if (tokens.length > _getMaxTokens()) {
            revert MaxTokens();
        }
    }

    function _getTotalTokens() internal view virtual returns (uint256);

    function _getMaxTokens() internal pure virtual returns (uint256);

    /**
     * @notice Return the current value of the swap fee percentage.
     */
    function getSwapFeePercentage() public pure virtual returns (uint256) {
        return _SWAP_FEE_PERCENTAGE;
    }

    /// TemporarilyPausable

    /**
     * @notice Pause the pool: an emergency action which disables all pool functions.
     * @dev This is a permissioned function that will only work during the Pause Window set during pool factory
     * deployment (see `TemporarilyPausable`).
     */
    function pause() external {
        _pause();
    }

    /**
     * @notice Reverse a `pause` operation, and restore a pool to normal functionality.
     * @dev This is a permissioned function that will only work on a paused pool within the Buffer Period set during
     * pool factory deployment (see `TemporarilyPausable`). Note that any paused pools will automatically unpause
     * after the Buffer Period expires.
     */
    function unpause() external {
        _unpause();
    }

    /// Callbacks

    function onAfterSwap(SwapParams calldata, uint256) external view virtual returns (bool) {
        revert CallbackNotImplemented();
    }

    function onAfterAddLiquidity(
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory,
        uint256[] memory,
        uint256
    ) external view virtual returns (bool) {
        revert CallbackNotImplemented();
    }

    function onAfterRemoveLiquidity(
        address,
        uint256[] memory,
        uint256[] memory,
        uint256,
        bytes memory,
        uint256[] memory
    ) external view virtual returns (bool) {
        revert CallbackNotImplemented();
    }

    /// Scaling

    /**
     * @dev Returns the scaling factor for one of the Pool's tokens. Reverts if `token` is not a token registered by the
     * Pool.
     *
     * All scaling factors are fixed-point values with 18 decimals, to allow for this function to be overridden by
     * derived contracts that need to apply further scaling, making these factors potentially non-integer.
     *
     * The largest 'base' scaling factor (i.e. in tokens with less than 18 decimals) is 10**18, which in fixed-point is
     * 10**36. This value can be multiplied with a 112 bit Vault balance with no overflow by a factor of ~1e7, making
     * even relatively 'large' factors safe to use.
     *
     * The 1e7 figure is the result of 2**256 / (1e18 * 1e18 * 2**112).
     */
    function _scalingFactor(IERC20 token) internal view virtual returns (uint256);

    /**
     * @dev Same as `_scalingFactor()`, except for all registered tokens (in the same order as registered). The Vault
     * will always pass balances in this order when calling any of the Pool callbacks.
     */
    function _scalingFactors() internal view virtual returns (uint256[] memory);

    function getScalingFactors() external view returns (uint256[] memory) {
        return _scalingFactors();
    }
}
