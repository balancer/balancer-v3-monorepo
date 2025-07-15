// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAggregatorRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IAggregatorRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/RouterTypes.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { SenderGuard } from "./SenderGuard.sol";
import { VaultGuard } from "./VaultGuard.sol";

import { RouterQueries } from "./RouterQueries.sol";
import { RouterCommon } from "./RouterCommon.sol";
import { RouterHooks } from "./RouterHooks.sol";

/**
 * @notice Entrypoint for aggregators who want to swap without the standard permit2 payment logic.
 * @dev The external API functions unlock the Vault, which calls back into the corresponding hook functions.
 */
contract AggregatorRouter is IAggregatorRouter, RouterHooks, RouterQueries {
    constructor(
        IVault vault,
        string memory routerVersion
    ) RouterQueries(vault, IWETH(address(0)), IPermit2(address(0)), true, routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    /// @inheritdoc IAggregatorRouter
    function addLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) external saveSender(msg.sender) returns (uint256[] memory amountsIn) {
        (amountsIn, , ) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    RouterHooks.addLiquidityHook,
                    AddLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        maxAmountsIn: maxAmountsIn,
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

    /// @inheritdoc IAggregatorRouter
    function addLiquidityUnbalanced(
        address pool,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external saveSender(msg.sender) returns (uint256 bptAmountOut) {
        (, bptAmountOut, ) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    RouterHooks.addLiquidityHook,
                    AddLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        maxAmountsIn: exactAmountsIn,
                        minBptAmountOut: minBptAmountOut,
                        kind: AddLiquidityKind.UNBALANCED,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256[], uint256, bytes)
        );
    }

    /// @inheritdoc IAggregatorRouter
    function addLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        uint256 maxAmountIn,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) external saveSender(msg.sender) returns (uint256 amountIn) {
        (uint256[] memory maxAmountsIn, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
            pool,
            tokenIn,
            maxAmountIn
        );

        (uint256[] memory amountsIn, , ) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    RouterHooks.addLiquidityHook,
                    AddLiquidityHookParams({
                        sender: msg.sender,
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

    /// @inheritdoc IAggregatorRouter
    function donate(address pool, uint256[] memory amountsIn, bytes memory userData) external saveSender(msg.sender) {
        _vault.unlock(
            abi.encodeCall(
                RouterHooks.addLiquidityHook,
                AddLiquidityHookParams({
                    sender: msg.sender,
                    pool: pool,
                    maxAmountsIn: amountsIn,
                    minBptAmountOut: 0,
                    kind: AddLiquidityKind.DONATION,
                    wethIsEth: false,
                    userData: userData
                })
            )
        );
    }

    /// @inheritdoc IAggregatorRouter
    function addLiquidityCustom(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    )
        external
        saveSender(msg.sender)
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData)
    {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        RouterHooks.addLiquidityHook,
                        AddLiquidityHookParams({
                            sender: msg.sender,
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

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    /// @inheritdoc IAggregatorRouter
    function removeLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) external saveSender(msg.sender) returns (uint256[] memory amountsOut) {
        (, amountsOut, ) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    RouterHooks.removeLiquidityHook,
                    RemoveLiquidityHookParams({
                        sender: msg.sender,
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

    /// @inheritdoc IAggregatorRouter
    function removeLiquiditySingleTokenExactIn(
        address pool,
        uint256 exactBptAmountIn,
        IERC20 tokenOut,
        uint256 minAmountOut,
        bytes memory userData
    ) external saveSender(msg.sender) returns (uint256 amountOut) {
        (uint256[] memory minAmountsOut, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
            pool,
            tokenOut,
            minAmountOut
        );

        (, uint256[] memory amountsOut, ) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    RouterHooks.removeLiquidityHook,
                    RemoveLiquidityHookParams({
                        sender: msg.sender,
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

    /// @inheritdoc IAggregatorRouter
    function removeLiquiditySingleTokenExactOut(
        address pool,
        uint256 maxBptAmountIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        bytes memory userData
    ) external saveSender(msg.sender) returns (uint256 bptAmountIn) {
        (uint256[] memory minAmountsOut, ) = _getSingleInputArrayAndTokenIndex(pool, tokenOut, exactAmountOut);

        (bptAmountIn, , ) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    RouterHooks.removeLiquidityHook,
                    RemoveLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        minAmountsOut: minAmountsOut,
                        maxBptAmountIn: maxBptAmountIn,
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

    /// @inheritdoc IAggregatorRouter
    function removeLiquidityCustom(
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        bytes memory userData
    )
        external
        saveSender(msg.sender)
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData)
    {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        RouterHooks.removeLiquidityHook,
                        RemoveLiquidityHookParams({
                            sender: msg.sender,
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

    /// @inheritdoc IAggregatorRouter
    function removeLiquidityRecovery(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut
    ) external returns (uint256[] memory amountsOut) {
        amountsOut = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    RouterHooks.removeLiquidityRecoveryHook,
                    (pool, msg.sender, exactBptAmountIn, minAmountsOut)
                )
            ),
            (uint256[])
        );
    }

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    /// @inheritdoc IAggregatorRouter
    function swapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bytes calldata userData
    ) public saveSender(msg.sender) returns (uint256) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        RouterHooks.swapSingleTokenHook,
                        SwapSingleTokenHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_IN,
                            pool: pool,
                            tokenIn: tokenIn,
                            tokenOut: tokenOut,
                            amountGiven: exactAmountIn,
                            limit: minAmountOut,
                            deadline: deadline,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    /// @inheritdoc IAggregatorRouter
    function swapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bytes calldata userData
    ) public saveSender(msg.sender) returns (uint256) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        RouterHooks.swapSingleTokenHook,
                        SwapSingleTokenHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_OUT,
                            pool: pool,
                            tokenIn: tokenIn,
                            tokenOut: tokenOut,
                            amountGiven: exactAmountOut,
                            limit: maxAmountIn,
                            deadline: deadline,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    /// @inheritdoc RouterCommon
    receive() external payable override {
        revert CannotReceiveEth();
    }
}
