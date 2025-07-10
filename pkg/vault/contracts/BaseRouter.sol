// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/RouterTypes.sol";

import { RouterWethLib } from "./lib/RouterWethLib.sol";
import { RouterQueries } from "./RouterQueries.sol";

/**
 * @notice Base Router with hooks for swaps and liquidity operations via Vault.
 * @dev Implements hooks for init, add liquidity, remove liquidity, and swaps.
 */
contract BaseRouter is RouterQueries {
    using Address for address payable;
    using RouterWethLib for IWETH;
    using SafeCast for *;

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2,
        string memory routerVersion
    ) RouterQueries(vault, weth, permit2, routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Hook for initialization.
     * @dev Can only be called by the Vault.
     * @param params Initialization parameters (see IRouter for struct definition)
     * @return bptAmountOut BPT amount minted in exchange for the input tokens
     */
    function initializeHook(
        InitializeHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256 bptAmountOut) {
        bptAmountOut = _vault.initialize(
            params.pool,
            params.sender,
            params.tokens,
            params.exactAmountsIn,
            params.minBptAmountOut,
            params.userData
        );

        for (uint256 i = 0; i < params.tokens.length; ++i) {
            IERC20 token = params.tokens[i];
            uint256 amountIn = params.exactAmountsIn[i];

            if (amountIn == 0) {
                continue;
            }

            // There can be only one WETH token in the pool.
            if (params.wethIsEth && address(token) == address(_weth)) {
                _weth.wrapEthAndSettle(_vault, amountIn);
            } else {
                // Transfer tokens from the user to the Vault.
                // Any value over MAX_UINT128 would revert above in `initialize`, so this SafeCast shouldn't be
                // necessary. Done out of an abundance of caution.
                _permit2.transferFrom(params.sender, address(_vault), amountIn.toUint160(), address(token));
                _vault.settle(token, amountIn);
            }
        }

        // Return ETH dust.
        _returnEth(params.sender);
    }

    /**
     * @notice Hook for adding liquidity.
     * @dev Can only be called by the Vault.
     * @param params Add liquidity parameters (see IRouter for struct definition)
     * @return amountsIn Actual amounts in required for the join
     * @return bptAmountOut BPT amount minted in exchange for the input tokens
     * @return returnData Arbitrary data with encoded response from the pool
     */
    function addLiquidityHook(
        AddLiquidityHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData)
    {
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

        // maxAmountsIn length is checked against tokens length at the Vault.
        IERC20[] memory tokens = _vault.getPoolTokens(params.pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 amountIn = amountsIn[i];

            if (amountIn == 0) {
                continue;
            }

            // There can be only one WETH token in the pool.
            if (params.wethIsEth && address(token) == address(_weth)) {
                _weth.wrapEthAndSettle(_vault, amountIn);
            } else {
                // Any value over MAX_UINT128 would revert above in `addLiquidity`, so this SafeCast shouldn't be
                // necessary. Done out of an abundance of caution.
                _permit2.transferFrom(params.sender, address(_vault), amountIn.toUint160(), address(token));
                _vault.settle(token, amountIn);
            }
        }

        // Send remaining ETH to the user.
        _returnEth(params.sender);
    }

    /**
     * @notice Hook for removing liquidity.
     * @dev Can only be called by the Vault.
     * @param params Remove liquidity parameters (see IRouter for struct definition)
     * @return bptAmountIn BPT amount burned for the output tokens
     * @return amountsOut Actual token amounts transferred in exchange for the BPT
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function removeLiquidityHook(
        RemoveLiquidityHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData)
    {
        (bptAmountIn, amountsOut, returnData) = _vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: params.pool,
                from: params.sender,
                maxBptAmountIn: params.maxBptAmountIn,
                minAmountsOut: params.minAmountsOut,
                kind: params.kind,
                userData: params.userData
            })
        );

        // minAmountsOut length is checked against tokens length at the Vault.
        IERC20[] memory tokens = _vault.getPoolTokens(params.pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amountOut = amountsOut[i];
            if (amountOut == 0) {
                continue;
            }

            IERC20 token = tokens[i];

            // There can be only one WETH token in the pool.
            if (params.wethIsEth && address(token) == address(_weth)) {
                _weth.unwrapWethAndTransferToSender(_vault, params.sender, amountOut);
            } else {
                // Transfer the token to the sender (amountOut).
                _vault.sendTo(token, params.sender, amountOut);
            }
        }

        _returnEth(params.sender);
    }

    /**
     * @notice Hook for removing liquidity in Recovery Mode.
     * @dev Can only be called by the Vault, when the pool is in Recovery Mode.
     * @param pool Address of the liquidity pool
     * @param sender Account originating the remove liquidity operation
     * @param exactBptAmountIn BPT amount burned for the output tokens
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @return amountsOut Actual token amounts transferred in exchange for the BPT
     */
    function removeLiquidityRecoveryHook(
        address pool,
        address sender,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut
    ) external nonReentrant onlyVault returns (uint256[] memory amountsOut) {
        amountsOut = _vault.removeLiquidityRecovery(pool, sender, exactBptAmountIn, minAmountsOut);

        IERC20[] memory tokens = _vault.getPoolTokens(pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amountOut = amountsOut[i];
            if (amountOut > 0) {
                // Transfer the token to the sender (amountOut).
                _vault.sendTo(tokens[i], sender, amountOut);
            }
        }

        _returnEth(sender);
    }

    /**
     * @notice Hook for swaps.
     * @dev Can only be called by the Vault. Also handles native ETH.
     * @param params Swap parameters (see IRouter for struct definition)
     * @return amountCalculated Token amount calculated by the pool math (e.g., amountOut for an exact in swap)
     */
    function swapSingleTokenHook(
        SwapSingleTokenHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256) {
        (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) = _swapHook(params);

        IERC20 tokenIn = params.tokenIn;

        _takeTokenIn(params.sender, tokenIn, amountIn, params.wethIsEth);
        _sendTokenOut(params.sender, params.tokenOut, amountOut, params.wethIsEth);

        if (tokenIn == _weth) {
            // Return the rest of ETH to sender
            _returnEth(params.sender);
        }

        return amountCalculated;
    }
}
