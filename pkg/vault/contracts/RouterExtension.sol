// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IRouterExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterExtension.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

import { Router } from "./Router.sol";
import { RouterCommon } from "./RouterCommon.sol";

contract RouterExtension is RouterCommon, ReentrancyGuardTransient, IRouterExtension {
    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2,
        string memory version
    ) RouterCommon(vault, weth, permit2, version) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /*******************************************************************************
                                      Queries
    *******************************************************************************/

    /// @inheritdoc IRouterExtension
    function queryAddLiquidityProportional(
        address pool,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256[] memory amountsIn) {
        (amountsIn, , ) = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    RouterExtension.queryAddLiquidityHook,
                    AddLiquidityHookParams({
                        // We use the Router as a sender to simplify basic query functions,
                        // but it is possible to add liquidity to any recipient.
                        sender: address(this),
                        pool: pool,
                        maxAmountsIn: _maxTokenLimits(pool),
                        minBptAmountOut: exactBptAmountOut,
                        kind: AddLiquidityKind.PROPORTIONAL,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256[], uint256, bytes)
        );
    }

    /// @inheritdoc IRouterExtension
    function queryAddLiquidityUnbalanced(
        address pool,
        uint256[] memory exactAmountsIn,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256 bptAmountOut) {
        (, bptAmountOut, ) = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    RouterExtension.queryAddLiquidityHook,
                    AddLiquidityHookParams({
                        // We use the Router as a sender to simplify basic query functions,
                        // but it is possible to add liquidity to any recipient.
                        sender: address(this),
                        pool: pool,
                        maxAmountsIn: exactAmountsIn,
                        minBptAmountOut: 0,
                        kind: AddLiquidityKind.UNBALANCED,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256[], uint256, bytes)
        );
    }

    /// @inheritdoc IRouterExtension
    function queryAddLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256 amountIn) {
        (uint256[] memory maxAmountsIn, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
            pool,
            tokenIn,
            _MAX_AMOUNT
        );

        (uint256[] memory amountsIn, , ) = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    RouterExtension.queryAddLiquidityHook,
                    AddLiquidityHookParams({
                        // We use the Router as a sender to simplify basic query functions,
                        // but it is possible to add liquidity to any recipient.
                        sender: address(this),
                        pool: pool,
                        maxAmountsIn: maxAmountsIn,
                        minBptAmountOut: exactBptAmountOut,
                        kind: AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256[], uint256, bytes)
        );

        return amountsIn[tokenIndex];
    }

    /// @inheritdoc IRouterExtension
    function queryAddLiquidityCustom(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        RouterExtension.queryAddLiquidityHook,
                        AddLiquidityHookParams({
                            // We use the Router as a sender to simplify basic query functions,
                            // but it is possible to add liquidity to any recipient.
                            sender: address(this),
                            pool: pool,
                            maxAmountsIn: maxAmountsIn,
                            minBptAmountOut: minBptAmountOut,
                            kind: AddLiquidityKind.CUSTOM,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256[], uint256, bytes)
            );
    }

    /// @inheritdoc IRouterExtension
    function queryAddLiquidityHook(
        AddLiquidityHookParams calldata params
    ) external onlyVault returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        (amountsIn, bptAmountOut, returnData) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: params.pool,
                to: params.sender,
                maxAmountsIn: params.maxAmountsIn,
                minBptAmountOut: params.minBptAmountOut,
                kind: params.kind,
                userData: params.userData
            })
        );
    }

    /// @inheritdoc IRouterExtension
    function queryRemoveLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256[] memory amountsOut) {
        uint256[] memory minAmountsOut = new uint256[](_vault.getPoolTokens(pool).length);
        (, amountsOut, ) = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    RouterExtension.queryRemoveLiquidityHook,
                    RemoveLiquidityHookParams({
                        // We use the Router as a sender to simplify basic query functions,
                        // but it is possible to remove liquidity from any sender.
                        sender: address(this),
                        pool: pool,
                        minAmountsOut: minAmountsOut,
                        maxBptAmountIn: exactBptAmountIn,
                        kind: RemoveLiquidityKind.PROPORTIONAL,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256, uint256[], bytes)
        );
    }

    /// @inheritdoc IRouterExtension
    function queryRemoveLiquiditySingleTokenExactIn(
        address pool,
        uint256 exactBptAmountIn,
        IERC20 tokenOut,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256 amountOut) {
        // We cannot use 0 as min amount out, as this value is used to figure out the token index.
        (uint256[] memory minAmountsOut, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(pool, tokenOut, 1);

        (, uint256[] memory amountsOut, ) = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    RouterExtension.queryRemoveLiquidityHook,
                    RemoveLiquidityHookParams({
                        // We use the Router as a sender to simplify basic query functions,
                        // but it is possible to remove liquidity from any sender.
                        sender: address(this),
                        pool: pool,
                        minAmountsOut: minAmountsOut,
                        maxBptAmountIn: exactBptAmountIn,
                        kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256, uint256[], bytes)
        );

        return amountsOut[tokenIndex];
    }

    /// @inheritdoc IRouterExtension
    function queryRemoveLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256 bptAmountIn) {
        (uint256[] memory minAmountsOut, ) = _getSingleInputArrayAndTokenIndex(pool, tokenOut, exactAmountOut);

        (bptAmountIn, , ) = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    RouterExtension.queryRemoveLiquidityHook,
                    RemoveLiquidityHookParams({
                        // We use the Router as a sender to simplify basic query functions,
                        // but it is possible to remove liquidity from any sender.
                        sender: address(this),
                        pool: pool,
                        minAmountsOut: minAmountsOut,
                        maxBptAmountIn: _MAX_AMOUNT,
                        kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256, uint256[], bytes)
        );

        return bptAmountIn;
    }

    /// @inheritdoc IRouterExtension
    function queryRemoveLiquidityCustom(
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        RouterExtension.queryRemoveLiquidityHook,
                        RemoveLiquidityHookParams({
                            // We use the Router as a sender to simplify basic query functions,
                            // but it is possible to remove liquidity from any sender.
                            sender: address(this),
                            pool: pool,
                            minAmountsOut: minAmountsOut,
                            maxBptAmountIn: maxBptAmountIn,
                            kind: RemoveLiquidityKind.CUSTOM,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256, uint256[], bytes)
            );
    }

    /// @inheritdoc IRouterExtension
    function queryRemoveLiquidityRecovery(
        address pool,
        uint256 exactBptAmountIn
    ) external returns (uint256[] memory amountsOut) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        RouterExtension.queryRemoveLiquidityRecoveryHook,
                        (pool, address(this), exactBptAmountIn)
                    )
                ),
                (uint256[])
            );
    }

    /// @inheritdoc IRouterExtension
    function queryRemoveLiquidityHook(
        RemoveLiquidityHookParams calldata params
    ) external onlyVault returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData) {
        return
            _vault.removeLiquidity(
                RemoveLiquidityParams({
                    pool: params.pool,
                    from: params.sender,
                    maxBptAmountIn: params.maxBptAmountIn,
                    minAmountsOut: params.minAmountsOut,
                    kind: params.kind,
                    userData: params.userData
                })
            );
    }

    /// @inheritdoc IRouterExtension
    function queryRemoveLiquidityRecoveryHook(
        address pool,
        address sender,
        uint256 exactBptAmountIn
    ) external onlyVault returns (uint256[] memory amountsOut) {
        return _vault.removeLiquidityRecovery(pool, sender, exactBptAmountIn);
    }

    /// @inheritdoc IRouterExtension
    function querySwapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256 amountCalculated) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        RouterExtension.querySwapHook,
                        IRouterCommon.SwapSingleTokenHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_IN,
                            pool: pool,
                            tokenIn: tokenIn,
                            tokenOut: tokenOut,
                            amountGiven: exactAmountIn,
                            limit: 0,
                            deadline: _MAX_AMOUNT,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    /// @inheritdoc IRouterExtension
    function querySwapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256 amountCalculated) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        RouterExtension.querySwapHook,
                        IRouterCommon.SwapSingleTokenHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_OUT,
                            pool: pool,
                            tokenIn: tokenIn,
                            tokenOut: tokenOut,
                            amountGiven: exactAmountOut,
                            limit: _MAX_AMOUNT,
                            deadline: type(uint256).max,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    /**
     * @notice Hook for swap queries.
     * @dev Can only be called by the Vault. Also handles native ETH.
     * @param params Swap parameters (see IRouter for struct definition)
     * @return amountCalculated Token amount calculated by the pool math (e.g., amountOut for a exact in swap)
     */
    function querySwapHook(
        IRouterCommon.SwapSingleTokenHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256) {
        (uint256 amountCalculated, , ) = _swapHook(params);

        return amountCalculated;
    }
}
