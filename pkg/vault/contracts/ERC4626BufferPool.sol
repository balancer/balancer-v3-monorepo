// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IBufferPool } from "@balancer-labs/v3-interfaces/contracts/vault/IBufferPool.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BalancerPoolToken } from "./BalancerPoolToken.sol";
import { BasePoolHooks } from "./BasePoolHooks.sol";

/**
 * @notice ERC4626 Buffer Pool, designed to be used internally for ERC4626 token types in standard pools.
 * @dev These "pools" reuse the code for pools, but are not registered with the Vault, guaranteeing they
 * cannot be used externally. To the outside world, they don't exist.
 */
contract ERC4626BufferPool is IBasePool, IBufferPool, IRateProvider, IPoolLiquidity, BalancerPoolToken, BasePoolHooks {
    uint256 private constant _DEFAULT_BUFFER_AMP_PARAMETER = 200;
    uint256 private constant _AMP_PRECISION = 1e3;

    IERC4626 internal immutable _wrappedToken;

    // TODO: At some point, allow changing this. Do we still need the rate limiting?
    uint256 private _amplificationParameter;

    constructor(
        string memory name,
        string memory symbol,
        IERC4626 wrappedToken,
        IVault vault
    ) BalancerPoolToken(vault, name, symbol) {
        _wrappedToken = wrappedToken;

        _amplificationParameter = _DEFAULT_BUFFER_AMP_PARAMETER * _AMP_PRECISION;
    }

    /// @inheritdoc IBasePool
    function getPoolTokens() public view onlyVault returns (IERC20[] memory tokens) {
        return getVault().getPoolTokens(address(this));
    }

    /// @inheritdoc BasePoolHooks
    function onBeforeInitialize(
        uint256[] memory exactAmountsInScaled18,
        bytes memory
    ) external view override onlyVault returns (bool) {
        // Enforce proportionality - might need to say exactAmountsIn[0].mulDown(getRate()) to compare equal value?
        return exactAmountsInScaled18.length == 2 && exactAmountsInScaled18[0] == exactAmountsInScaled18[1];
    }

    /// @inheritdoc BasePoolHooks
    function onBeforeAddLiquidity(
        address,
        AddLiquidityKind kind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) external view override onlyVault returns (bool) {
        if (kind != AddLiquidityKind.CUSTOM) {
            revert IVaultErrors.OperationNotSupported();
        }

        return true;
    }

    /// @inheritdoc IPoolLiquidity
    function onAddLiquidityCustom(
        address,
        uint256[] memory,
        uint256 exactBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory
    )
        external
        view
        onlyVault
        returns (uint256[] memory amountsInScaled18, uint256 bptAmountOut, bytes memory returnData)
    {
        // This is a proportional join
        bptAmountOut = exactBptAmountOut;
        returnData = "";

        amountsInScaled18 = BasePoolMath.computeProportionalAmountsIn(balancesScaled18, bptAmountOut, totalSupply());
    }

    /// @inheritdoc BasePoolHooks
    function onBeforeRemoveLiquidity(
        address,
        RemoveLiquidityKind kind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external view override onlyVault returns (bool) {
        if (kind != RemoveLiquidityKind.PROPORTIONAL) {
            revert IVaultErrors.OperationNotSupported();
        }

        return true;
    }

    /// @inheritdoc BasePoolHooks
    function onBeforeSwap(IBasePool.SwapParams calldata request) external view override onlyVault returns (bool) {
        // Swaps cannot be called externally
        if (request.sender != address(getVault())) {
            revert IVaultErrors.SenderIsNotVault(request.sender);
        }

        // TODO implement - check for / perform rebalancing; call _rebalance() if needed
        return true;
    }

    /// @inheritdoc IBasePool
    function onSwap(IBasePool.SwapParams memory request) public view onlyVault returns (uint256) {
        uint256 invariant = StableMath.computeInvariant(_amplificationParameter, request.balancesScaled18);

        if (request.kind == SwapKind.EXACT_IN) {
            uint256 amountOutScaled18 = StableMath.computeOutGivenExactIn(
                _amplificationParameter,
                request.balancesScaled18,
                request.indexIn,
                request.indexOut,
                request.amountGivenScaled18,
                invariant
            );

            return amountOutScaled18;
        } else {
            uint256 amountInScaled18 = StableMath.computeInGivenExactOut(
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

    /// @inheritdoc IRateProvider
    function getRate() external view onlyVault returns (uint256) {
        return _wrappedToken.convertToAssets(FixedPoint.ONE);
    }

    /// @inheritdoc IBufferPool
    function rebalance() external onlyVault {
        _rebalance();
    }

    function _rebalance() private {
        // TODO: implement - can be called by the pool during a swap, or from the Vault directly
    }

    // Unsupported functions that unconditionally revert

    /// @inheritdoc IBasePool
    function computeBalance(
        uint256[] memory, // balancesLiveScaled18,
        uint256, // tokenInIndex,
        uint256 // invariantRatio
    ) external pure returns (uint256) {
        // This pool doesn't support single token add/remove liquidity, so this function is not needed.
        // Should never get here, but need to implement the interface.
        revert IVaultErrors.OperationNotSupported();
    }

    /// @inheritdoc IPoolLiquidity
    function onRemoveLiquidityCustom(
        address,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external pure returns (uint256, uint256[] memory, bytes memory) {
        // Should throw `DoesNotSupportRemoveLiquidityCustom` before getting here, but need to implement the interface.
        revert IVaultErrors.OperationNotSupported();
    }
}
