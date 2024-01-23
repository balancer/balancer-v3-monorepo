// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";

import { BalancerPoolToken } from "./BalancerPoolToken.sol";

/**
 * @notice ERC4626 Buffer Pool, designed to be used internally for ERC4626 token types in standard pools.
 * @dev These "pools" reuse the code for pools, but are not registered with the Vault, guaranteeing they
 * cannot be used externally. To the outside world, they don't exist.
 */
contract ERC4626BufferPool is IBasePool, IRateProvider, BalancerPoolToken {
    uint256 private constant _DEFAULT_BUFFER_AMP_PARAMETER = 200;
    uint256 private constant _AMP_PRECISION = 1e3;

    IERC4626 internal immutable _wrappedToken;

    uint256 internal immutable _rateScalingFactor;

    // TODO: At some point, allow changing this. Do we still need the rate limiting?
    uint256 private _amplificationParameter;

    /// @dev Error thrown when a pool function is not supported.
    error NotImplemented();

    constructor(
        string memory name,
        string memory symbol,
        IERC4626 wrappedToken,
        IVault vault
    ) BalancerPoolToken(vault, name, symbol) {
        _wrappedToken = wrappedToken;

        _amplificationParameter = _DEFAULT_BUFFER_AMP_PARAMETER * _AMP_PRECISION;

        // Compute the decimal difference (used for yield token rate computation).
        _rateScalingFactor = 10 ** (18 + wrappedToken.decimals() - IERC20Metadata(wrappedToken.asset()).decimals());
    }

    /// @inheritdoc IBasePool
    function getPoolTokens() public view onlyVault returns (IERC20[] memory tokens) {
        return getVault().getPoolTokens(address(this));
    }

    /// @inheritdoc IBasePool
    function onSwap(IBasePool.SwapParams memory request) public view onlyVault returns (uint256) {
        uint256 invariant = StableMath.computeInvariant(_amplificationParameter, request.balancesScaled18);

        if (request.kind == SwapKind.GIVEN_IN) {
            uint256 amountOutScaled18 = StableMath.computeOutGivenIn(
                _amplificationParameter,
                request.balancesScaled18,
                request.indexIn,
                request.indexOut,
                request.amountGivenScaled18,
                invariant
            );

            return amountOutScaled18;
        } else {
            uint256 amountInScaled18 = StableMath.computeInGivenOut(
                _amplificationParameter,
                request.balancesScaled18,
                request.indexIn,
                request.indexOut,
                request.amountGivenScaled18,
                invariant
            );

            return amountInScaled18;
        }
    }

    /// @inheritdoc IBasePool
    function computeInvariant(uint256[] memory balancesLiveScaled18) public view onlyVault returns (uint256) {
        return StableMath.computeInvariant(_amplificationParameter, balancesLiveScaled18);
    }

    /// @inheritdoc IBasePool
    function computeBalance(
        uint256[] memory, // balancesLiveScaled18,
        uint256, // tokenInIndex,
        uint256 // invariantRatio
    ) external pure returns (uint256) {
        // This pool doesn't support single token add/remove liquidity, so this function is not needed.
        revert NotImplemented();
    }

    /**
     * @notice Get the current rate of a wrapped token buffer, also scaled for decimals.
     * @return rate The current rate as an 18-decimal FP value, incorporating decimals
     */
    function getRate() external view onlyVault returns (uint256) {
        return _wrappedToken.convertToAssets(_rateScalingFactor);
    }
}
