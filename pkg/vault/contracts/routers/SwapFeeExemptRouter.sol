// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { ISwapFeeExemptRouter } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeeExemptRouter.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { RouterCommon } from "../RouterCommon.sol";

/**
 * @notice Basic router for swap operations.
 * @dev Phase 1: Open router that anyone can use for swaps with any pool.
 */
contract SwapFeeExemptRouter is ISwapFeeExemptRouter, RouterCommon {
    using SafeERC20 for IERC20;
    using Address for address payable;

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2,
        string memory routerVersion
    ) RouterCommon(vault, weth, permit2, routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc ISwapFeeExemptRouter
    function swapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable saveSender(msg.sender) returns (uint256 amountOut) {
        return abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    SwapFeeExemptRouter.swapSingleTokenHook,
                    IRouter.SwapSingleTokenHookParams({
                        sender: msg.sender,
                        kind: SwapKind.EXACT_IN,
                        pool: pool,
                        tokenIn: tokenIn,
                        tokenOut: tokenOut,
                        amountGiven: exactAmountIn,
                        limit: minAmountOut,
                        deadline: deadline,
                        wethIsEth: wethIsEth,
                        userData: userData
                    })
                )
            ),
            (uint256)
        );
    }

    /// @inheritdoc ISwapFeeExemptRouter
    function swapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable saveSender(msg.sender) returns (uint256 amountIn) {
        return abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    SwapFeeExemptRouter.swapSingleTokenHook,
                    IRouter.SwapSingleTokenHookParams({
                        sender: msg.sender,
                        kind: SwapKind.EXACT_OUT,
                        pool: pool,
                        tokenIn: tokenIn,
                        tokenOut: tokenOut,
                        amountGiven: exactAmountOut,
                        limit: maxAmountIn,
                        deadline: deadline,
                        wethIsEth: wethIsEth,
                        userData: userData
                    })
                )
            ),
            (uint256)
        );
    }

    /**
     * @notice Hook for swaps.
     * @dev Can only be called by the Vault. Handles native ETH.
     * @param params Swap parameters
     * @return calculatedAmount Token amount calculated by the pool math
     */
    function swapSingleTokenHook(
        IRouter.SwapSingleTokenHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256 calculatedAmount) {
        // Execute the swap
        (calculatedAmount, , ) = _vault.swap(
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

        // Handle token transfers
        uint256 amountIn = params.kind == SwapKind.EXACT_IN ? params.amountGiven : calculatedAmount;
        uint256 amountOut = params.kind == SwapKind.EXACT_IN ? calculatedAmount : params.amountGiven;

        _takeTokenIn(params.sender, params.tokenIn, amountIn, params.wethIsEth);
        _sendTokenOut(params.sender, params.tokenOut, amountOut, params.wethIsEth);

        if (params.tokenIn == _weth) {
            // Return the rest of ETH to sender
            _returnEth(params.sender);
        }
    }
}