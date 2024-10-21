// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { IAggRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IAggRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

import { RouterCommon } from "./RouterCommon.sol";

contract AggRouter is IAggRouter, RouterCommon, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using Address for address payable;

    constructor(IVault vault, IWETH weth, IPermit2 permit2) RouterCommon(vault, weth, permit2) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IAggRouter
    function swapSingleTokenDonated(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable saveSender(msg.sender) returns (uint256) {
        return
            abi.decode(
                _vault.unlock(
                    _swapSingleTokenArgs(
                        pool,
                        tokenIn,
                        tokenOut,
                        exactAmountIn,
                        minAmountOut,
                        deadline,
                        wethIsEth,
                        userData
                    )
                ),
                (uint256)
            );
    }

    // Addresses stack-too-deep.
    function _swapSingleTokenArgs(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) private view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                AggRouter.swapSingleTokenDonatedHook.selector,
                SwapSingleTokenHookParams({
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
            );
    }

    /**
     * @notice Hook for swaps.
     * @dev Can only be called by the Vault. Also handles native ETH.
     * @param params Swap parameters (see IRouter for struct definition)
     * @return Token amount calculated by the pool math (e.g., amountOut for a exact in swap)
     */
    function swapSingleTokenDonatedHook(
        SwapSingleTokenHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256) {
        (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) = _swapHook(params);

        IERC20 tokenIn = params.tokenIn;

        _vault.settle(tokenIn, amountIn);
        _sendTokenOut(params.sender, params.tokenOut, amountOut, params.wethIsEth);

        if (tokenIn == _weth) {
            // Return the rest of ETH to sender
            _returnEth(params.sender);
        }

        return amountCalculated;
    }

    function _swapHook(
        SwapSingleTokenHookParams calldata params
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
}
