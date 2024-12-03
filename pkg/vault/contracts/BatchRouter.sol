// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import {
    TransientEnumerableSet
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/TransientEnumerableSet.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

import { BatchRouterCommon } from "./BatchRouterCommon.sol";

struct SwapStepLocals {
    bool isFirstStep;
    bool isLastStep;
}

/**
 * @notice Entrypoint for batch swaps, and batch swap queries.
 * @dev The external API functions unlock the Vault, which calls back into the corresponding hook functions.
 * These interpret the steps and paths in the input data, perform token accounting (in transient storage, to save gas),
 * settle with the Vault, and handle wrapping and unwrapping ETH.
 */
contract BatchRouter is IBatchRouter, BatchRouterCommon {
    using CastingHelpers for *;
    using TransientEnumerableSet for TransientEnumerableSet.AddressSet;
    using TransientStorageHelpers for *;
    using SafeERC20 for IERC20;
    using SafeCast for *;

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2,
        string memory routerVersion
    ) BatchRouterCommon(vault, weth, permit2, routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    /// @inheritdoc IBatchRouter
    function swapExactIn(
        SwapPathExactAmountIn[] memory paths,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    )
        external
        payable
        saveSender(msg.sender)
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        BatchRouter.swapExactInHook,
                        SwapExactInHookParams({
                            sender: msg.sender,
                            paths: paths,
                            deadline: deadline,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256[], address[], uint256[])
            );
    }

    /// @inheritdoc IBatchRouter
    function swapExactOut(
        SwapPathExactAmountOut[] memory paths,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    )
        external
        payable
        saveSender(msg.sender)
        returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn)
    {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        BatchRouter.swapExactOutHook,
                        SwapExactOutHookParams({
                            sender: msg.sender,
                            paths: paths,
                            deadline: deadline,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256[], address[], uint256[])
            );
    }

    function swapExactInHook(
        SwapExactInHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        (pathAmountsOut, tokensOut, amountsOut) = _swapExactInHook(params);

        _settlePaths(params.sender, params.wethIsEth);
    }

    function _swapExactInHook(
        SwapExactInHookParams calldata params
    ) internal returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) {
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > params.deadline) {
            revert SwapDeadline();
        }

        pathAmountsOut = _computePathAmountsOut(params);

        // The hook writes current swap token and token amounts out.
        // We copy that information to memory to return it before it is deleted during settlement.
        tokensOut = _currentSwapTokensOut().values();
        amountsOut = new uint256[](tokensOut.length);
        for (uint256 i = 0; i < tokensOut.length; ++i) {
            amountsOut[i] =
                _currentSwapTokenOutAmounts().tGet(tokensOut[i]) +
                _settledTokenAmounts().tGet(tokensOut[i]);
            _settledTokenAmounts().tSet(tokensOut[i], 0);
        }
    }

    function _computePathAmountsOut(
        SwapExactInHookParams calldata params
    ) internal returns (uint256[] memory pathAmountsOut) {
        pathAmountsOut = new uint256[](params.paths.length);

        for (uint256 i = 0; i < params.paths.length; ++i) {
            SwapPathExactAmountIn memory path = params.paths[i];

            // These two variables shall be updated at the end of each step to be used as inputs of the next one.
            // The initial values are the given token and amount in for the current path.
            uint256 stepExactAmountIn = path.exactAmountIn;
            IERC20 stepTokenIn = path.tokenIn;

            if (path.steps[0].isBuffer && EVMCallModeHelpers.isStaticCall() == false) {
                // If first step is a buffer, take the token in advance. We need this to wrap/unwrap.
                _takeTokenIn(params.sender, stepTokenIn, stepExactAmountIn, params.wethIsEth);
            } else {
                // Paths may (or may not) share the same token in. To minimize token transfers, we store the addresses
                // in a set with unique addresses that can be iterated later on.
                // For example, if all paths share the same token in, the set will end up with only one entry.
                _currentSwapTokensIn().add(address(stepTokenIn));
                _currentSwapTokenInAmounts().tAdd(address(stepTokenIn), stepExactAmountIn);
            }

            for (uint256 j = 0; j < path.steps.length; ++j) {
                SwapStepLocals memory stepLocals;
                stepLocals.isLastStep = (j == path.steps.length - 1);
                stepLocals.isFirstStep = (j == 0);
                uint256 minAmountOut;

                // minAmountOut only applies to the last step.
                if (stepLocals.isLastStep) {
                    minAmountOut = path.minAmountOut;
                } else {
                    minAmountOut = 0;
                }

                SwapPathStep memory step = path.steps[j];

                if (step.isBuffer) {
                    (, , uint256 amountOut) = _vault.erc4626BufferWrapOrUnwrap(
                        BufferWrapOrUnwrapParams({
                            kind: SwapKind.EXACT_IN,
                            direction: step.pool == address(stepTokenIn)
                                ? WrappingDirection.UNWRAP
                                : WrappingDirection.WRAP,
                            wrappedToken: IERC4626(step.pool),
                            amountGivenRaw: stepExactAmountIn,
                            limitRaw: minAmountOut
                        })
                    );

                    if (stepLocals.isLastStep) {
                        // The amount out for the last step of the path should be recorded for the return value, and the
                        // amount for the token should be sent back to the sender later on.
                        pathAmountsOut[i] = amountOut;
                        _currentSwapTokensOut().add(address(step.tokenOut));
                        _currentSwapTokenOutAmounts().tAdd(address(step.tokenOut), amountOut);
                    } else {
                        // Input for the next step is output of current step.
                        stepExactAmountIn = amountOut;
                        // The token in for the next step is the token out of the current step.
                        stepTokenIn = step.tokenOut;
                    }
                } else if (address(stepTokenIn) == step.pool) {
                    // Token in is BPT: remove liquidity - Single token exact in

                    // Remove liquidity is not transient when it comes to BPT, meaning the caller needs to have the
                    // required amount when performing the operation. These tokens might be the output of a previous
                    // step, in which case the user will have a BPT credit.

                    if (stepLocals.isFirstStep) {
                        if (stepExactAmountIn > 0 && params.sender != address(this)) {
                            // If this is the first step, the sender must have the tokens. Therefore, we can transfer
                            // them to the Router, which acts as an intermediary. If the sender is the Router, we just
                            // skip this step (useful for queries).
                            //
                            // This saves one permit(1) approval for the BPT to the Router; if we burned tokens
                            // directly from the sender we would need their approval.
                            _permit2.transferFrom(
                                params.sender,
                                address(this),
                                stepExactAmountIn.toUint160(),
                                address(stepTokenIn)
                            );
                        }

                        // BPT is burned instantly, so we don't need to send it back later.
                        if (_currentSwapTokenInAmounts().tGet(address(stepTokenIn)) > 0) {
                            _currentSwapTokenInAmounts().tSub(address(stepTokenIn), stepExactAmountIn);
                        }
                    } else {
                        // If this is an intermediate step, we don't expect the sender to have BPT to burn.
                        // Then, we flashloan tokens here (which should in practice just use existing credit).
                        _vault.sendTo(IERC20(step.pool), address(this), stepExactAmountIn);
                    }

                    // minAmountOut cannot be 0 in this case, as that would send an array of 0s to the Vault, which
                    // wouldn't know which token to use.
                    (uint256[] memory amountsOut, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
                        step.pool,
                        step.tokenOut,
                        minAmountOut == 0 ? 1 : minAmountOut
                    );

                    // Router is always an intermediary in this case. The Vault will burn tokens from the Router, so
                    // Router is both owner and spender (which doesn't need approval).
                    // Reusing `amountsOut` as input argument and function output to prevent stack too deep error.
                    (, amountsOut, ) = _vault.removeLiquidity(
                        RemoveLiquidityParams({
                            pool: step.pool,
                            from: address(this),
                            maxBptAmountIn: stepExactAmountIn,
                            minAmountsOut: amountsOut,
                            kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                            userData: params.userData
                        })
                    );

                    if (stepLocals.isLastStep) {
                        // The amount out for the last step of the path should be recorded for the return value, and the
                        // amount for the token should be sent back to the sender later on.
                        pathAmountsOut[i] = amountsOut[tokenIndex];
                        _currentSwapTokensOut().add(address(step.tokenOut));
                        _currentSwapTokenOutAmounts().tAdd(address(step.tokenOut), amountsOut[tokenIndex]);
                    } else {
                        // Input for the next step is output of current step.
                        stepExactAmountIn = amountsOut[tokenIndex];
                        // The token in for the next step is the token out of the current step.
                        stepTokenIn = step.tokenOut;
                    }
                } else if (address(step.tokenOut) == step.pool) {
                    // Token out is BPT: add liquidity - Single token exact in (unbalanced).
                    (uint256[] memory exactAmountsIn, ) = _getSingleInputArrayAndTokenIndex(
                        step.pool,
                        stepTokenIn,
                        stepExactAmountIn
                    );

                    (, uint256 bptAmountOut, ) = _vault.addLiquidity(
                        AddLiquidityParams({
                            pool: step.pool,
                            to: stepLocals.isLastStep ? params.sender : address(_vault),
                            maxAmountsIn: exactAmountsIn,
                            minBptAmountOut: minAmountOut,
                            kind: AddLiquidityKind.UNBALANCED,
                            userData: params.userData
                        })
                    );

                    if (stepLocals.isLastStep) {
                        // The amount out for the last step of the path should be recorded for the return value.
                        // We do not need to register the amount out in _currentSwapTokenOutAmounts since the BPT
                        // is minted directly to the sender, so this step can be considered settled at this point.
                        pathAmountsOut[i] = bptAmountOut;
                        _currentSwapTokensOut().add(address(step.tokenOut));
                        _settledTokenAmounts().tAdd(address(step.tokenOut), bptAmountOut);
                    } else {
                        // Input for the next step is output of current step.
                        stepExactAmountIn = bptAmountOut;
                        // The token in for the next step is the token out of the current step.
                        stepTokenIn = step.tokenOut;
                        // If this is an intermediate step, BPT is minted to the Vault so we just get the credit.
                        _vault.settle(IERC20(step.pool), bptAmountOut);
                    }
                } else {
                    // No BPT involved in the operation: regular swap exact in.
                    (, , uint256 amountOut) = _vault.swap(
                        VaultSwapParams({
                            kind: SwapKind.EXACT_IN,
                            pool: step.pool,
                            tokenIn: stepTokenIn,
                            tokenOut: step.tokenOut,
                            amountGivenRaw: stepExactAmountIn,
                            limitRaw: minAmountOut,
                            userData: params.userData
                        })
                    );

                    if (stepLocals.isLastStep) {
                        // The amount out for the last step of the path should be recorded for the return value, and the
                        // amount for the token should be sent back to the sender later on.
                        pathAmountsOut[i] = amountOut;
                        _currentSwapTokensOut().add(address(step.tokenOut));
                        _currentSwapTokenOutAmounts().tAdd(address(step.tokenOut), amountOut);
                    } else {
                        // Input for the next step is output of current step.
                        stepExactAmountIn = amountOut;
                        // The token in for the next step is the token out of the current step.
                        stepTokenIn = step.tokenOut;
                    }
                }
            }
        }
    }

    function swapExactOutHook(
        SwapExactOutHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn)
    {
        (pathAmountsIn, tokensIn, amountsIn) = _swapExactOutHook(params);

        _settlePaths(params.sender, params.wethIsEth);
    }

    function _swapExactOutHook(
        SwapExactOutHookParams calldata params
    ) internal returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) {
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > params.deadline) {
            revert SwapDeadline();
        }

        pathAmountsIn = _computePathAmountsIn(params);

        // The hook writes current swap token and token amounts in.
        // We copy that information to memory to return it before it is deleted during settlement.
        tokensIn = _currentSwapTokensIn().values(); // Copy transient storage to memory
        amountsIn = new uint256[](tokensIn.length);
        for (uint256 i = 0; i < tokensIn.length; ++i) {
            amountsIn[i] = _currentSwapTokenInAmounts().tGet(tokensIn[i]) + _settledTokenAmounts().tGet(tokensIn[i]);
            _settledTokenAmounts().tSet(tokensIn[i], 0);
        }
    }

    /**
     * @dev Executes every swap path in the given input parameters.
     * Computes inputs for the path, and aggregates them by token and amounts as well in transient storage.
     */
    function _computePathAmountsIn(
        SwapExactOutHookParams calldata params
    ) internal returns (uint256[] memory pathAmountsIn) {
        pathAmountsIn = new uint256[](params.paths.length);

        for (uint256 i = 0; i < params.paths.length; ++i) {
            SwapPathExactAmountOut memory path = params.paths[i];
            // This variable shall be updated at the end of each step to be used as input of the next one.
            // The first value corresponds to the given amount out for the current path.
            uint256 stepExactAmountOut = path.exactAmountOut;

            // Paths may (or may not) share the same token in. To minimize token transfers, we store the addresses in
            // a set with unique addresses that can be iterated later on.
            //
            // For example, if all paths share the same token in, the set will end up with only one entry.
            // Since the path is 'given out', the output of the operation specified by the last step in each path will
            // be added to calculate the amounts in for each token.
            _currentSwapTokensIn().add(address(path.tokenIn));

            // Backwards iteration: the exact amount out applies to the last step, so we cannot iterate from first to
            // last. The calculated input of step (j) is the exact amount out for step (j - 1).
            for (int256 j = int256(path.steps.length - 1); j >= 0; --j) {
                SwapPathStep memory step = path.steps[uint256(j)];
                SwapStepLocals memory stepLocals;
                stepLocals.isLastStep = (j == 0);
                stepLocals.isFirstStep = (uint256(j) == path.steps.length - 1);

                // These two variables are set at the beginning of the iteration and are used as inputs for
                // the operation described by the step.
                uint256 stepMaxAmountIn;
                IERC20 stepTokenIn;

                if (stepLocals.isFirstStep) {
                    // The first step in the iteration is the last one in the given array of steps, and it
                    // specifies the output token for the step as well as the exact amount out for that token.
                    // Output amounts are stored to send them later on.
                    _currentSwapTokensOut().add(address(step.tokenOut));
                    _currentSwapTokenOutAmounts().tAdd(address(step.tokenOut), stepExactAmountOut);
                }

                if (stepLocals.isLastStep) {
                    // In backwards order, the last step is the first one in the given path.
                    // The given token in and max amount in apply for this step.
                    stepMaxAmountIn = path.maxAmountIn;
                    stepTokenIn = path.tokenIn;
                } else {
                    // For every other intermediate step, no maximum input applies.
                    // The input token for this step is the output token of the previous given step.
                    // We use uint128 to prevent Vault's internal scaling from overflowing.
                    stepMaxAmountIn = _MAX_AMOUNT;
                    stepTokenIn = path.steps[uint256(j - 1)].tokenOut;
                }

                if (step.isBuffer) {
                    if (stepLocals.isLastStep && EVMCallModeHelpers.isStaticCall() == false) {
                        // The buffer will need this token to wrap/unwrap, so take it from the user in advance.
                        _takeTokenIn(params.sender, path.tokenIn, path.maxAmountIn, params.wethIsEth);
                    }

                    (, uint256 amountIn, ) = _vault.erc4626BufferWrapOrUnwrap(
                        BufferWrapOrUnwrapParams({
                            kind: SwapKind.EXACT_OUT,
                            direction: step.pool == address(stepTokenIn)
                                ? WrappingDirection.UNWRAP
                                : WrappingDirection.WRAP,
                            wrappedToken: IERC4626(step.pool),
                            amountGivenRaw: stepExactAmountOut,
                            limitRaw: stepMaxAmountIn
                        })
                    );

                    if (stepLocals.isLastStep) {
                        pathAmountsIn[i] = amountIn;
                        // Since the token was taken in advance, returns to the user what is left from the
                        // wrap/unwrap operation.
                        _currentSwapTokensOut().add(address(stepTokenIn));
                        _currentSwapTokenOutAmounts().tAdd(address(stepTokenIn), path.maxAmountIn - amountIn);
                        // `settledTokenAmounts` is used to return the `amountsIn` at the end of the operation, which
                        // is only amountIn. The difference between maxAmountIn and amountIn will be paid during
                        // settle.
                        _settledTokenAmounts().tAdd(address(path.tokenIn), amountIn);
                    } else {
                        stepExactAmountOut = amountIn;
                    }
                } else if (address(stepTokenIn) == step.pool) {
                    // Token in is BPT: remove liquidity - Single token exact out

                    // Remove liquidity is not transient when it comes to BPT, meaning the caller needs to have the
                    // required amount when performing the operation. In this case, the BPT amount needed for the
                    // operation is not known in advance, so we take a flashloan for all the available reserves.
                    //
                    // The last step is the one that defines the inputs for this path. The caller should have enough
                    // BPT to burn already if that's the case, so we just skip this step if so.
                    if (stepLocals.isLastStep == false) {
                        stepMaxAmountIn = _vault.getReservesOf(stepTokenIn);
                        _vault.sendTo(IERC20(step.pool), address(this), stepMaxAmountIn);
                    } else if (params.sender != address(this)) {
                        // The last step being executed is the first step in the swap path, meaning that it's the one
                        // that defines the inputs of the path.
                        //
                        // In that case, the sender must have the tokens. Therefore, we can transfer them
                        // to the Router, which acts as an intermediary. If the sender is the Router, we just skip this
                        // step (useful for queries).
                        _permit2.transferFrom(
                            params.sender,
                            address(this),
                            stepMaxAmountIn.toUint160(),
                            address(stepTokenIn)
                        );
                    }

                    (uint256[] memory exactAmountsOut, ) = _getSingleInputArrayAndTokenIndex(
                        step.pool,
                        step.tokenOut,
                        stepExactAmountOut
                    );

                    // Router is always an intermediary in this case. The Vault will burn tokens from the Router, so
                    // Router is both owner and spender (which doesn't need approval).
                    (uint256 bptAmountIn, , ) = _vault.removeLiquidity(
                        RemoveLiquidityParams({
                            pool: step.pool,
                            from: address(this),
                            maxBptAmountIn: stepMaxAmountIn,
                            minAmountsOut: exactAmountsOut,
                            kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                            userData: params.userData
                        })
                    );

                    if (stepLocals.isLastStep) {
                        // BPT is burned instantly, so we don't need to send it to the Vault during settlement.
                        pathAmountsIn[i] = bptAmountIn;
                        _settledTokenAmounts().tAdd(address(stepTokenIn), bptAmountIn);

                        // Refund unused portion of BPT to the user.alias
                        if (bptAmountIn < stepMaxAmountIn && params.sender != address(this)) {
                            stepTokenIn.safeTransfer(address(params.sender), stepMaxAmountIn - bptAmountIn);
                        }
                    } else {
                        // Output for the step (j - 1) is the input of step (j).
                        stepExactAmountOut = bptAmountIn;
                        // Refund unused portion of BPT flashloan to the Vault.
                        if (bptAmountIn < stepMaxAmountIn) {
                            uint256 refundAmount = stepMaxAmountIn - bptAmountIn;
                            stepTokenIn.safeTransfer(address(_vault), refundAmount);
                            _vault.settle(stepTokenIn, refundAmount);
                        }
                    }
                } else if (address(step.tokenOut) == step.pool) {
                    // Token out is BPT: add liquidity - Single token exact out.
                    (uint256[] memory stepAmountsIn, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
                        step.pool,
                        stepTokenIn,
                        stepMaxAmountIn
                    );

                    // Reusing `amountsIn` as input argument and function output to prevent stack too deep error.
                    (stepAmountsIn, , ) = _vault.addLiquidity(
                        AddLiquidityParams({
                            pool: step.pool,
                            to: stepLocals.isFirstStep ? params.sender : address(_vault),
                            maxAmountsIn: stepAmountsIn,
                            minBptAmountOut: stepExactAmountOut,
                            kind: AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                            userData: params.userData
                        })
                    );

                    if (stepLocals.isLastStep) {
                        // The amount out for the last step of the path should be recorded for the return value.
                        pathAmountsIn[i] = stepAmountsIn[tokenIndex];
                        _currentSwapTokenInAmounts().tAdd(address(stepTokenIn), stepAmountsIn[tokenIndex]);
                    } else {
                        stepExactAmountOut = stepAmountsIn[tokenIndex];
                    }

                    // The first step executed determines the outputs for the path, since this is given out.
                    if (stepLocals.isFirstStep) {
                        // Instead of sending tokens back to the Vault, we can just discount it from whatever
                        // the Vault owes the sender to make one less transfer.
                        _currentSwapTokenOutAmounts().tSub(address(step.tokenOut), stepExactAmountOut);
                    } else {
                        // If it's not the first step, BPT is minted to the Vault so we just get the credit.
                        _vault.settle(IERC20(step.pool), stepExactAmountOut);
                    }
                } else {
                    // No BPT involved in the operation: regular swap exact out.
                    (, uint256 amountIn, ) = _vault.swap(
                        VaultSwapParams({
                            kind: SwapKind.EXACT_OUT,
                            pool: step.pool,
                            tokenIn: stepTokenIn,
                            tokenOut: step.tokenOut,
                            amountGivenRaw: stepExactAmountOut,
                            limitRaw: stepMaxAmountIn,
                            userData: params.userData
                        })
                    );

                    if (stepLocals.isLastStep) {
                        pathAmountsIn[i] = amountIn;
                        _currentSwapTokenInAmounts().tAdd(address(stepTokenIn), amountIn);
                    } else {
                        stepExactAmountOut = amountIn;
                    }
                }
            }
        }
    }

    /***************************************************************************
                                     Queries
    ***************************************************************************/

    /// @inheritdoc IBatchRouter
    function querySwapExactIn(
        SwapPathExactAmountIn[] memory paths,
        address sender,
        bytes calldata userData
    )
        external
        saveSender(sender)
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        for (uint256 i = 0; i < paths.length; ++i) {
            paths[i].minAmountOut = 0;
        }

        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        BatchRouter.querySwapExactInHook,
                        SwapExactInHookParams({
                            sender: address(this),
                            paths: paths,
                            deadline: type(uint256).max,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256[], address[], uint256[])
            );
    }

    /// @inheritdoc IBatchRouter
    function querySwapExactOut(
        SwapPathExactAmountOut[] memory paths,
        address sender,
        bytes calldata userData
    )
        external
        saveSender(sender)
        returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn)
    {
        for (uint256 i = 0; i < paths.length; ++i) {
            paths[i].maxAmountIn = _MAX_AMOUNT;
        }

        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        BatchRouter.querySwapExactOutHook,
                        SwapExactOutHookParams({
                            sender: address(this),
                            paths: paths,
                            deadline: type(uint256).max,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256[], address[], uint256[])
            );
    }

    function querySwapExactInHook(
        SwapExactInHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        (pathAmountsOut, tokensOut, amountsOut) = _swapExactInHook(params);
    }

    function querySwapExactOutHook(
        SwapExactOutHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn)
    {
        (pathAmountsIn, tokensIn, amountsIn) = _swapExactOutHook(params);
    }
}
