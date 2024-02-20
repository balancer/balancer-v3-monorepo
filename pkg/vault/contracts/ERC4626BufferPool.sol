// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IBufferPool, RebalanceHookParams } from "@balancer-labs/v3-interfaces/contracts/vault/IBufferPool.sol";
import {
    AddLiquidityKind,
    RemoveLiquidityKind,
    SwapParams as VaultSwapParams,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BasePoolAuthentication } from "./BasePoolAuthentication.sol";
import { BalancerPoolToken } from "./BalancerPoolToken.sol";
import { BasePoolHooks } from "./BasePoolHooks.sol";

/**
 * @notice ERC4626 Buffer Pool, designed to be used internally for ERC4626 token types in standard pools.
 * @dev These "pools" reuse the code for pools, but are not registered with the Vault, guaranteeing they
 * cannot be used externally. To the outside world, they don't exist.
 */
contract ERC4626BufferPool is
    IBasePool,
    IBufferPool,
    IRateProvider,
    IPoolLiquidity,
    BalancerPoolToken,
    BasePoolHooks,
    BasePoolAuthentication,
    ReentrancyGuard
{
    using FixedPoint for uint256;

    IERC4626 internal immutable _wrappedToken;

    // Uses the factory as the Authentication disambiguator.
    constructor(
        string memory name,
        string memory symbol,
        IERC4626 wrappedToken,
        IVault vault
    ) BalancerPoolToken(vault, name, symbol) BasePoolAuthentication(vault, msg.sender) {
        _wrappedToken = wrappedToken;
    }

    /// @inheritdoc IBasePool
    function getPoolTokens() public view onlyVault returns (IERC20[] memory tokens) {
        return getVault().getPoolTokens(address(this));
    }

    /// @inheritdoc BasePoolHooks
    function onBeforeInitialize(
        uint256[] memory exactAmountsInScaled18,
        bytes memory
    ) external view virtual override onlyVault returns (bool) {
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
        // Only support custom add liquidity.
        return kind == AddLiquidityKind.CUSTOM;
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
        returns (
            uint256[] memory amountsInScaled18,
            uint256 bptAmountOut,
            uint256[] memory swapFeeAmountsScaled18,
            bytes memory returnData
        )
    {
        // This is a proportional join
        bptAmountOut = exactBptAmountOut;
        returnData = "";

        amountsInScaled18 = BasePoolMath.computeProportionalAmountsIn(balancesScaled18, bptAmountOut, totalSupply());
        swapFeeAmountsScaled18 = new uint256[](balancesScaled18.length);
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
        // Only support proportional remove liquidity.
        return kind == RemoveLiquidityKind.PROPORTIONAL;
    }

    /// @inheritdoc BasePoolHooks
    function onBeforeSwap(IBasePool.SwapParams calldata) external view override onlyVault returns (bool) {
        // Swaps cannot be called externally - only the Vault can call this.
        // Since routers might still try to trade directly with buffer pools (either maliciously or accidentally),
        // the Vault also explicitly blocks any swaps with buffer pools.

        // TODO implement - check for / perform rebalancing; call _rebalance() if needed
        // Exact mechanism TBD. Might call back to the Vault with a special operation (that can only be called from
        // a Buffer Pool) to move the token balances, asset manager style.
        return true;
    }

    /// @inheritdoc IBasePool
    function onSwap(IBasePool.SwapParams memory request) public view onlyVault returns (uint256) {
        return request.amountGivenScaled18;
    }

    /// @inheritdoc IBasePool
    function computeInvariant(uint256[] memory balancesLiveScaled18) public view onlyVault returns (uint256) {
        return balancesLiveScaled18[0] + balancesLiveScaled18[1];
    }

    /// @inheritdoc IRateProvider
    function getRate() external view onlyVault returns (uint256) {
        return _getRate();
    }

    /// @inheritdoc IBufferPool
    function rebalance() external {
        // TODO reinsert authenticate modifier
        _rebalance();
    }

    /// @dev Non-reentrant to ensure we don't try to externally rebalance during an internal rebalance.
    function _rebalance() internal nonReentrant {
        address poolAddress = address(this);

        // Get balance of tokens
        (IERC20[] memory tokens, , uint256[] memory rawBalances, , ) = getVault().getPoolTokenInfo(poolAddress);

        uint256 scaledBalanceWrapped = _wrappedToken.previewRedeem(rawBalances[0]);
        uint256 balanceUnderlying = rawBalances[1];

        if (scaledBalanceWrapped > balanceUnderlying) {
            uint256 assetsToUnwrap = (scaledBalanceWrapped - balanceUnderlying) / 2;

            abi.decode(
                getVault().invoke{ value: msg.value }(
                    abi.encodeWithSelector(
                        ERC4626BufferPool.rebalanceHook.selector,
                        RebalanceHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_IN,
                            pool: poolAddress,
                            tokenIn: tokens[1],
                            tokenOut: tokens[0],
                            amountGiven: assetsToUnwrap,
                            limit: assetsToUnwrap / 2 // TODO Review limit and deadline
                        })
                    )
                ),
                (uint256)
            );
        } else if (balanceUnderlying > scaledBalanceWrapped) {
            uint256 assetsToWrap = (balanceUnderlying - scaledBalanceWrapped) / 2;

            abi.decode(
                getVault().invoke{ value: msg.value }(
                    abi.encodeWithSelector(
                        ERC4626BufferPool.rebalanceHook.selector,
                        RebalanceHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_OUT,
                            pool: poolAddress,
                            tokenIn: tokens[0],
                            tokenOut: tokens[1],
                            amountGiven: assetsToWrap,
                            limit: assetsToWrap * 2 // TODO Review limit and deadline
                        })
                    )
                ),
                (uint256)
            );
        }
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
    ) external pure returns (uint256, uint256[] memory, uint256[] memory, bytes memory) {
        // Should throw `DoesNotSupportRemoveLiquidityCustom` before getting here, but need to implement the interface.
        revert IVaultErrors.OperationNotSupported();
    }

    // TODO Check why nonReentrant modifier fails in this hook. Where is the reentrancy?
    function rebalanceHook(RebalanceHookParams calldata params) external payable onlyVault returns (uint256) {
        (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) = _swapHook(params);

        if (params.kind == SwapKind.EXACT_IN) {
            IERC20 underlyingToken = params.tokenIn;
            IERC20 wrappedToken = params.tokenOut;

            getVault().wire(wrappedToken, address(this), amountOut);
            IERC4626(address(wrappedToken)).withdraw(amountIn, address(this), address(this));
            underlyingToken.approve(address(getVault()), amountIn);
            getVault().retrieve(underlyingToken, address(this), amountIn);
        } else {
            IERC20 underlyingToken = params.tokenOut;
            IERC20 wrappedToken = params.tokenIn;

            getVault().wire(underlyingToken, address(this), amountOut);
            underlyingToken.approve(address(wrappedToken), amountOut);
            IERC4626(address(wrappedToken)).deposit(amountOut, address(this));
            wrappedToken.approve(address(getVault()), amountIn);
            getVault().retrieve(wrappedToken, address(this), amountIn);
        }

        return amountCalculated;
    }

    function _swapHook(
        RebalanceHookParams calldata params
    ) internal returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) {
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        //        if (block.timestamp > params.deadline) {
        //            revert SwapDeadline();
        //        }

        (amountCalculated, amountIn, amountOut) = getVault().swap(
            VaultSwapParams({
                kind: params.kind,
                pool: params.pool,
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                amountGivenRaw: params.amountGiven,
                limitRaw: params.limit,
                userData: new bytes(0)
            })
        );
    }

    function _getRate() private view returns (uint256) {
        return _wrappedToken.convertToAssets(FixedPoint.ONE);
    }
}
