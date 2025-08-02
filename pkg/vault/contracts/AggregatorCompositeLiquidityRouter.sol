// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { ICompositeLiquidityRouter } from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/RouterTypes.sol";

import { CompositeLiquidityRouterHooks } from "./CompositeLiquidityRouterHooks.sol";
import { CompositeLiquidityRouterQueries } from "./CompositeLiquidityRouterQueries.sol";

/**
 * @notice An aggregator composite liquidity router for liquidity operations on ERC4626 and nested pools.
 * @dev This contract allows interacting with ERC4626 Pools (which contain wrapped ERC4626 tokens) using only standard
 * underlying tokens. For instance, with `addLiquidityUnbalancedToERC4626Pool` it is possible to add liquidity to an
 * ERC4626 Pool with [waDAI, waUSDC], using only DAI, only USDC, or an arbitrary amount of both. If the ERC4626 buffers
 * in the Vault have liquidity, these will be used to avoid wrapping/unwrapping through the wrapped token interface,
 * saving gas.
 *
 * For instance, adding only DAI to the pool above (and assuming a waDAI buffer with enough liquidity), would pull in
 * the DAI from the user, swap it for waDAI in the internal Vault buffer, and deposit the waDAI into the ERC4626 pool:
 * 1) without having to do any expensive ERC4626 wrapping operations; and
 * 2) without requiring the user to construct a batch operation containing the buffer swap.
 *
 * The aggregator composite liquidity router is designed to be called from a contract vs. an EOA through a UI.
 * It uses prepayment instead of permit2.
 */
contract AggregatorCompositeLiquidityRouter is ICompositeLiquidityRouter, CompositeLiquidityRouterQueries {
    constructor(
        IVault vault,
        IWETH weth,
        string memory routerVersion
    ) CompositeLiquidityRouterQueries(vault, weth, IPermit2(address(0)), true, routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /*******************************************************************************
                                ERC4626 Pools
    *******************************************************************************/

    /// @inheritdoc ICompositeLiquidityRouter
    function addLiquidityUnbalancedToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256 bptAmountOut) {
        bptAmountOut = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    CompositeLiquidityRouterHooks.addLiquidityERC4626PoolUnbalancedHook,
                    (
                        AddLiquidityHookParams({
                            sender: msg.sender,
                            pool: pool,
                            maxAmountsIn: exactAmountsIn,
                            minBptAmountOut: minBptAmountOut,
                            kind: AddLiquidityKind.UNBALANCED,
                            wethIsEth: wethIsEth,
                            userData: userData
                        }),
                        wrapUnderlying
                    )
                )
            ),
            (uint256)
        );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function addLiquidityProportionalToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256[] memory) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        CompositeLiquidityRouterHooks.addLiquidityERC4626PoolProportionalHook,
                        (
                            AddLiquidityHookParams({
                                sender: msg.sender,
                                pool: pool,
                                maxAmountsIn: maxAmountsIn,
                                minBptAmountOut: exactBptAmountOut,
                                kind: AddLiquidityKind.PROPORTIONAL,
                                wethIsEth: wethIsEth,
                                userData: userData
                            }),
                            wrapUnderlying
                        )
                    )
                ),
                (uint256[])
            );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function removeLiquidityProportionalFromERC4626Pool(
        address pool,
        bool[] memory unwrapWrapped,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256[] memory) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        CompositeLiquidityRouterHooks.removeLiquidityERC4626PoolProportionalHook,
                        (
                            RemoveLiquidityHookParams({
                                sender: msg.sender,
                                pool: pool,
                                minAmountsOut: minAmountsOut,
                                maxBptAmountIn: exactBptAmountIn,
                                kind: RemoveLiquidityKind.PROPORTIONAL,
                                wethIsEth: wethIsEth,
                                userData: userData
                            }),
                            unwrapWrapped
                        )
                    )
                ),
                (uint256[])
            );
    }

    /***************************************************************************
                                   Nested pools
    ***************************************************************************/

    /// @inheritdoc ICompositeLiquidityRouter
    function addLiquidityUnbalancedNestedPool(
        address parentPool,
        address[] memory tokensIn,
        uint256[] memory exactAmountsIn,
        address[] memory tokensToWrap,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        CompositeLiquidityRouterHooks.addLiquidityUnbalancedNestedPoolHook,
                        (
                            AddLiquidityHookParams({
                                pool: parentPool,
                                sender: msg.sender,
                                maxAmountsIn: exactAmountsIn,
                                minBptAmountOut: minBptAmountOut,
                                kind: AddLiquidityKind.UNBALANCED,
                                wethIsEth: wethIsEth,
                                userData: userData
                            }),
                            tokensIn,
                            tokensToWrap
                        )
                    )
                ),
                (uint256)
            );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function removeLiquidityProportionalNestedPool(
        address parentPool,
        uint256 exactBptAmountIn,
        address[] memory tokensOut,
        uint256[] memory minAmountsOut,
        address[] memory tokensToUnwrap,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256[] memory amountsOut) {
        amountsOut = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    CompositeLiquidityRouterHooks.removeLiquidityProportionalNestedPoolHook,
                    (
                        RemoveLiquidityHookParams({
                            sender: msg.sender,
                            pool: parentPool,
                            minAmountsOut: minAmountsOut,
                            maxBptAmountIn: exactBptAmountIn,
                            kind: RemoveLiquidityKind.PROPORTIONAL,
                            wethIsEth: wethIsEth,
                            userData: userData
                        }),
                        tokensOut,
                        tokensToUnwrap
                    )
                )
            ),
            (uint256[])
        );
    }
}
