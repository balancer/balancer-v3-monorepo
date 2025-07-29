// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import {
    IAggregatorCompositeLiquidityRouter
} from "@balancer-labs/v3-interfaces/contracts/vault/IAggregatorCompositeLiquidityRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/RouterTypes.sol";

import { CompositeLiquidityRouterHooks } from "./CompositeLiquidityRouterHooks.sol";
import { CompositeLiquidityRouterQueries } from "./CompositeLiquidityRouterQueries.sol";

/**
 * @notice Entrypoint for add/remove liquidity operations on ERC4626 and nested pools.
 * @dev The external API functions unlock the Vault, which calls back into the corresponding hook functions.
 * These execute the steps needed to add to and remove liquidity from these special types of pools, and settle
 * the operation with the Vault.
 *
 * The implementation calls into the `CompositeLiquidityRouterHooks` base contract, and is identical to
 * `CompositeLiquidityRouter`, except for hard-coding wethIsEth to false.
 */
contract AggregatorCompositeLiquidityRouter is IAggregatorCompositeLiquidityRouter, CompositeLiquidityRouterQueries {
    constructor(
        IVault vault,
        string memory routerVersion
    ) CompositeLiquidityRouterQueries(vault, IWETH(address(0)), IPermit2(address(0)), true, routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /*******************************************************************************
                                ERC4626 Pools
    *******************************************************************************/

    /// @inheritdoc IAggregatorCompositeLiquidityRouter
    function addLiquidityUnbalancedToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
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
                            wethIsEth: false,
                            userData: userData
                        }),
                        wrapUnderlying
                    )
                )
            ),
            (uint256)
        );
    }

    /// @inheritdoc IAggregatorCompositeLiquidityRouter
    function addLiquidityProportionalToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
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
                                wethIsEth: false,
                                userData: userData
                            }),
                            wrapUnderlying
                        )
                    )
                ),
                (uint256[])
            );
    }

    /// @inheritdoc IAggregatorCompositeLiquidityRouter
    function removeLiquidityProportionalFromERC4626Pool(
        address pool,
        bool[] memory unwrapWrapped,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
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
                                wethIsEth: false,
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

    /// @inheritdoc IAggregatorCompositeLiquidityRouter
    function addLiquidityUnbalancedNestedPool(
        address parentPool,
        address[] memory tokensIn,
        uint256[] memory exactAmountsIn,
        address[] memory tokensToWrap,
        uint256 minBptAmountOut,
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
                                wethIsEth: false,
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

    /// @inheritdoc IAggregatorCompositeLiquidityRouter
    function removeLiquidityProportionalNestedPool(
        address parentPool,
        uint256 exactBptAmountIn,
        address[] memory tokensOut,
        uint256[] memory minAmountsOut,
        address[] memory tokensToUnwrap,
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
                            wethIsEth: false,
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
