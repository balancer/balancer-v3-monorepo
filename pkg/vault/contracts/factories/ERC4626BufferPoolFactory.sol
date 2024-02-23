// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { ERC4626BufferPool } from "../ERC4626BufferPool.sol";
import { BasePoolFactory } from "./BasePoolFactory.sol";

/**
 * @notice Factory for ERC4626 Buffer Pools
 * @dev These are internal pools used with "Boosted Pools" to provide a reservoir of base tokens to support swaps.
 */
contract ERC4626BufferPoolFactory is BasePoolFactory {
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    /// @dev The wrapped token does not conform to the Vault's requirement for ERC4626-compatibility.
    error IncompatibleWrappedToken(address token);

    constructor(
        IVault vault,
        uint256 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, type(ERC4626BufferPool).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `ERC4626BufferPool`.
     * @dev Buffers might need an external pause manager (e.g., a large depositor). This is permissionless,
     * so anyone can create a buffer for any wrapper. As a safety measure, we validate the wrapper for
     * ERC4626-compatibility.
     *
     * @param wrappedToken The ERC4626 wrapped token associated with the buffer and pool
     * @param pauseManager The pause manager for this pool (or 0)
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(IERC4626 wrappedToken, address pauseManager, bytes32 salt) external returns (address pool) {
        // Ensure the wrappedToken is compatible with the Vault
        if (_isValidWrappedToken(wrappedToken) == false) {
            revert IncompatibleWrappedToken(address(wrappedToken));
        }

        pool = _create(
            abi.encode(
                string.concat("Balancer Buffer-", wrappedToken.name()),
                string.concat("BB-", wrappedToken.symbol()),
                wrappedToken,
                getVault()
            ),
            salt
        );

        getVault().registerBuffer(wrappedToken, pool, pauseManager, getNewPoolPauseWindowEndTime());

        _registerPoolWithFactory(pool);
    }

    /**
     * @dev Since creating buffers is permissionless, we want to make some effort to ensure that a new wrapper will be
     * well-behaved and compatible with the Vault. Of course, there are no guarantees, but we perform some basic checks.
     * @param wrappedToken The proposed token to create a new buffer for
     */
    function _isValidWrappedToken(IERC4626 wrappedToken) internal view returns (bool) {
        return _hasValidAsset(wrappedToken) && _hasAssetValue(wrappedToken) && _supportsRateComputation(wrappedToken);
    }

    /// @dev Wrappers must specify their underlying asset.
    function _hasValidAsset(IERC4626 wrappedToken) private view returns (bool) {
        try wrappedToken.asset() returns (address asset) {
            return asset != address(0);
        } catch {
            return false;
        }
    }

    /// @dev Wrappers must contain some value
    function _hasAssetValue(IERC4626 wrappedToken) private view returns (bool) {
        try wrappedToken.totalAssets() returns (uint256 totalAssets) {
            return totalAssets > 0;
        } catch {
            return false;
        }
    }

    /**
     * @dev We want to check that the shares/assets rates are consistent.
     * The easiest way to do this is preview withdrawals and redemptions with a unit asset.
     * These values should be reciprocals of each other, so multiplying them together should
     * equal ONE.
     *
     * There is a deep assumption here that although the ERC4626 standard does not define `getRate` directly,
     * we can derive a rate in this fashion that behaves like all other rate providers. Specifically, we mean
     * that, at least conceptually, there is a stable underlying "rate" that is constant over the full range
     * of input values. For instance, convertToAssets(60) + converToAssets(40) = convertToAssets(100).
     */
    function _supportsRateComputation(IERC4626 wrappedToken) private view returns (bool) {
        address asset = wrappedToken.asset();

        // We need to pass in the unit asset in native decimals.
        uint256 oneAsset = 10 ** IERC20Metadata(asset).decimals();
        uint256 oneShare = 10 ** wrappedToken.decimals();

        // Rounding with < 18 decimal tokens can cause the rate to deviate slightly from ONE,
        // so we set a tolerance proportional to the decimal difference
        // (e.g., 1 wei for 18-decimals; 1e12 for 6 decimals).
        uint256 tolerance = 10 ** (18 - IERC20Metadata(asset).decimals());

        // We scale up the returned values to 18-decimals for the multiplication.
        uint256 assetScalingFactor = ScalingHelpers.computeScalingFactor(IERC20(asset));
        uint256 shareScalingFactor = ScalingHelpers.computeScalingFactor(IERC20(wrappedToken));
        uint256 rateTest;

        try wrappedToken.previewRedeem(oneShare) returns (uint256 redeemedAssets) {
            rateTest = redeemedAssets.toScaled18RoundDown(assetScalingFactor);

            try wrappedToken.previewWithdraw(oneAsset) returns (uint256 redeemedShares) {
                // previewRedeem and previewWithdraw should be reciprocals,
                // so multiplying them should equal ONE
                rateTest = rateTest.mulDown(redeemedShares.toScaled18RoundUp(shareScalingFactor));

                // Should be very close to ONE
                uint256 diff = rateTest >= FixedPoint.ONE ? rateTest - FixedPoint.ONE : FixedPoint.ONE - rateTest;

                return diff <= tolerance;
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }
}
