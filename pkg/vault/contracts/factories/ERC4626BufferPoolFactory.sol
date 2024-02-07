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
    function _isValidWrappedToken(IERC4626 wrappedToken) private view returns (bool) {
        // Wrappers must specify their underlying asset.
        try wrappedToken.asset() returns (address asset) {
            if (asset == address(0)) {
                return false;
            } else {
                // Wrappers must contain some value
                try wrappedToken.totalAssets() returns (uint256 totalAssets) {
                    if (totalAssets > 0) {
                        // We want to check that the shares/assets rates are consistent.
                        // The easiest way to do this is preview withdrawals and redemptions with a unit asset.
                        // These values should be reciprocals of each other, so multiplying them together should
                        // equal ONE.
                        //
                        // We need to pass in the unit asset in native decimals.
                        uint256 oneAsset = 10 ** IERC20Metadata(asset).decimals();
                        // Rounding with < 18 decimal tokens can cause the rate to deviate slightly from ONE,
                        // so we set a tolerance proportional to the decimal difference
                        // (e.g., 1 wei for 18-decimals; 1e12 for 6 decimals).
                        uint256 tolerance = 10 ** (18 - IERC20Metadata(asset).decimals());
                        // We scale up the returned values to 18-decimals for the multiplication.
                        uint256 assetScalingFactor = ScalingHelpers.computeScalingFactor(IERC20(asset));
                        uint256 rateTest;

                        try wrappedToken.previewRedeem(oneAsset) returns (uint256 redeemRate) {
                            rateTest = redeemRate.toScaled18RoundDown(assetScalingFactor);

                            try wrappedToken.previewWithdraw(oneAsset) returns (uint256 withdrawRate) {
                                // previewRedeem and previewWithdraw should be reciprocals,
                                // so multiplying them should equal ONE
                                rateTest = rateTest.mulDown(withdrawRate.toScaled18RoundDown(assetScalingFactor));

                                // Should be very close to ONE
                                uint256 diff = rateTest >= FixedPoint.ONE
                                    ? rateTest - FixedPoint.ONE
                                    : FixedPoint.ONE - rateTest;

                                return diff <= tolerance;
                            } catch {
                                return false;
                            }
                        } catch {
                            return false;
                        }
                    } else {
                        return false;
                    }
                } catch {
                    return false;
                }
            }
        } catch {
            return false;
        }
    }
}
