// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IAggregatorRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IAggregatorRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

import { SenderGuard } from "./SenderGuard.sol";

import { VaultGuard } from "./VaultGuard.sol";

/**
 * @notice Entrypoint for aggregators who want to swap without the standard permit2 payment logic.
 * @dev The external API functions unlock the Vault, which calls back into the corresponding hook functions.
 * These interact with the Vault and settle accounting. This is not a full-featured Router; it only implements
 * `swapSingleTokenExactIn`, `swapSingleTokenExactOut`, and the associated queries.
 */
contract AggregatorRouter is IAggregatorRouter, SenderGuard, VaultGuard, ReentrancyGuardTransient, Version {
    constructor(IVault vault, string memory routerVersion) SenderGuard() VaultGuard(vault) Version(routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IAggregatorRouter
    function getVault() public view returns (IVault) {
        return _vault;
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
    ) external saveSender(msg.sender) returns (uint256) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        AggregatorRouter.swapSingleTokenHook,
                        IRouter.SwapSingleTokenHookParams({
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
    ) external saveSender(msg.sender) returns (uint256) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        AggregatorRouter.swapSingleTokenHook,
                        IRouter.SwapSingleTokenHookParams({
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

    /**
     * @notice Hook for swaps.
     * @dev Can only be called by the Vault. This router expects the caller to pay upfront by sending tokens to the
     * Vault directly, so this call only accounts for the amount that has already been paid, skipping transfers of
     * any kind (specifically, the permit2 transfers triggered by the standard Router).
     *
     * @param params Swap parameters (see IRouter for the struct definition)
     * @return amountCalculated Token amount calculated by the pool math (e.g., amountOut for an exact in swap)
     */
    function swapSingleTokenHook(
        IRouter.SwapSingleTokenHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256) {
        // `amountInHint` represents the amount supposedly paid upfront by the sender.
        uint256 amountInHint;
        if (params.kind == SwapKind.EXACT_IN) {
            amountInHint = params.amountGiven;
        } else {
            amountInHint = params.limit;
        }

        // Always settle the amount paid first to prevent potential underflows at the vault. `tokenInCredit`
        // represents the amount actually paid by the sender, which can be at most `amountInHint`.
        // If the user paid less than what was expected, revert early.
        uint256 tokenInCredit = _vault.settle(params.tokenIn, amountInHint);
        if (tokenInCredit < amountInHint) {
            revert SwapInsufficientPayment();
        }

        (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) = _swapHook(params);

        if (params.kind == SwapKind.EXACT_OUT) {
            // Transfer any leftovers back to the sender (amount actually paid minus amount required for the swap).
            // At this point, the Vault already validated that `tokenInCredit > amountIn`.
            _sendTokenOut(params.sender, params.tokenIn, tokenInCredit - amountIn);
        }

        // Finally, settle the output token by sending the credited tokens to the sender.
        _sendTokenOut(params.sender, params.tokenOut, amountOut);

        return amountCalculated;
    }

    function _swapHook(
        IRouter.SwapSingleTokenHookParams calldata params
    ) internal returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) {
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > params.deadline) {
            revert SwapDeadline();
        }

        (amountCalculated, amountIn, amountOut) = _vault.swap(
            VaultSwapParams({
                kind: params.kind,
                pool: params.pool,
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                amountGivenRaw: params.amountGiven,
                limitRaw: params.limit,
                userData: params.userData
            })
        );
    }

    /*******************************************************************************
                                      Queries
    *******************************************************************************/

    /// @inheritdoc IAggregatorRouter
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
                        AggregatorRouter.querySwapHook,
                        IRouter.SwapSingleTokenHookParams({
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

    /// @inheritdoc IAggregatorRouter
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
                        AggregatorRouter.querySwapHook,
                        IRouter.SwapSingleTokenHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_OUT,
                            pool: pool,
                            tokenIn: tokenIn,
                            tokenOut: tokenOut,
                            amountGiven: exactAmountOut,
                            limit: _MAX_AMOUNT,
                            deadline: _MAX_AMOUNT,
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
     * @dev Can only be called by the Vault.
     * @param params Swap parameters (see IRouter for struct definition)
     * @return amountCalculated Token amount calculated by the pool math (e.g., amountOut for an exact in swap)
     */
    function querySwapHook(
        IRouter.SwapSingleTokenHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256) {
        (uint256 amountCalculated, , ) = _swapHook(params);

        return amountCalculated;
    }

    function _sendTokenOut(address sender, IERC20 tokenOut, uint256 amountOut) internal {
        if (amountOut == 0) {
            return;
        }

        _vault.sendTo(tokenOut, sender, amountOut);
    }

    receive() external payable {
        revert CannotReceiveEth();
    }
}
