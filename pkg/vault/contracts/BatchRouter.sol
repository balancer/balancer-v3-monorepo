// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";

import { RouterCommon } from "./RouterCommon.sol";

contract BatchRouter is IBatchRouter, RouterCommon, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // We use transient storage to track tokens and amounts flowing in and out of a batch swap.
    // Set of input tokens involved in a batch swap.
    EnumerableSet.AddressSet private _currentSwapTokensIn;
    // Set of output tokens involved in a batch swap.
    EnumerableSet.AddressSet private _currentSwapTokensOut;
    // token in -> amount: tracks token in amounts within a batch swap.
    mapping(address => uint256) private _currentSwapTokenInAmounts;
    // token out -> amount: tracks token out amounts within a batch swap.
    mapping(address => uint256) private _currentSwapTokenOutAmounts;
    // token -> amount that is part of the current input / output amounts, but is settled preemptively.
    // This situation happens whenever there is BPT involved in the operation, which is minted and burnt instantly.
    // Since those amounts are not tracked in the inputs / outputs to settle, we need to track them elsewhere
    // to return the correct total amounts in and out for each token involved in the operation.
    mapping(address => uint256) private _settledTokenAmounts;

    constructor(IVault vault, IWETH weth, IPermit2 permit2) RouterCommon(vault, weth, permit2) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IBatchRouter
    function swapExactIn(
        SwapPathExactAmountIn[] memory paths,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    )
        external
        payable
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        return
            abi.decode(
                _vault.lock{ value: msg.value }(
                    abi.encodeWithSelector(
                        BatchRouter.swapExactInHook.selector,
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
    ) external payable returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) {
        return
            abi.decode(
                _vault.lock{ value: msg.value }(
                    abi.encodeWithSelector(
                        BatchRouter.swapExactOutHook.selector,
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
        payable
        nonReentrant
        onlyVault
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        // If path has a flag shouldPayFirst, collects the tokens from user before computePath
        // (tokens will be wrapped)
        for (uint256 i = 0; i < params.paths.length; i++) {
            SwapPathExactAmountIn memory path = params.paths[i];

            if (path.shouldPayFirst) {
                _takeTokenIn(params.sender, path.tokenIn, path.exactAmountIn, false);
                _currentSwapTokensOut.add(address(path.tokenIn));
                _currentSwapTokenOutAmounts[address(path.tokenIn)] += path.exactAmountIn;
            }
        }

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
        tokensOut = _currentSwapTokensOut._values;
        amountsOut = new uint256[](tokensOut.length);
        for (uint256 i = 0; i < tokensOut.length; ++i) {
            amountsOut[i] = _currentSwapTokenOutAmounts[tokensOut[i]] + _settledTokenAmounts[tokensOut[i]];
            _settledTokenAmounts[tokensOut[i]] = 0;
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

            // TODO: this should be transient.
            // Paths may (or may not) share the same token in. To minimize token transfers, we store the addresses in
            // a set with unique addresses that can be iterated later on.
            // For example, if all paths share the same token in, the set will end up with only one entry.
            if (_currentSwapTokenOutAmounts[address(stepTokenIn)] > stepExactAmountIn) {
                _currentSwapTokenOutAmounts[address(stepTokenIn)] -= stepExactAmountIn;
            } else {
                _currentSwapTokensIn.add(address(stepTokenIn));
                if (_currentSwapTokenOutAmounts[address(stepTokenIn)] > 0) {
                    _currentSwapTokenInAmounts[address(stepTokenIn)] +=
                        stepExactAmountIn -
                        _currentSwapTokenOutAmounts[address(stepTokenIn)];
                    _currentSwapTokensOut.remove(address(stepTokenIn));
                    _currentSwapTokenOutAmounts[address(stepTokenIn)] = 0;
                } else {
                    _currentSwapTokenInAmounts[address(stepTokenIn)] += stepExactAmountIn;
                }
            }

            for (uint256 j = 0; j < path.steps.length; ++j) {
                bool isLastStep = (j == path.steps.length - 1);
                uint256 minAmountOut;

                // minAmountOut only applies to the last step.
                if (isLastStep) {
                    minAmountOut = path.minAmountOut;
                } else {
                    minAmountOut = 0;
                }

                SwapPathStep memory step = path.steps[j];

                if (!path.shouldPayFirst && address(stepTokenIn) == step.pool) {
                    // Token in is BPT: remove liquidity - Single token exact in

                    // Remove liquidity is not transient when it comes to BPT, meaning the caller needs to have the
                    // required amount when performing the operation. These tokens might be the output of a previous
                    // step, in which case the user will have a BPT credit.
                    if (IVault(_vault).getTokenDelta(address(this), stepTokenIn) < 0) {
                        _vault.sendTo(IERC20(step.pool), params.sender, stepExactAmountIn);
                    }
                    // BPT is burnt instantly, so we don't need to send it back later.
                    if (_currentSwapTokenInAmounts[address(stepTokenIn)] > 0) {
                        _currentSwapTokenInAmounts[address(stepTokenIn)] -= stepExactAmountIn;
                    }

                    // minAmountOut cannot be 0 in this case, as that would send an array of 0s to the Vault, which
                    // wouldn't know which token to use.
                    (uint256[] memory amountsOut, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
                        step.pool,
                        step.tokenOut,
                        minAmountOut == 0 ? 1 : minAmountOut
                    );

                    // Reusing `amountsOut` as input argument and function output to prevent stack too deep error.
                    if (params.sender == address(this)) {
                        // Needed for queries.
                        // If router is the sender, it has to approve itself.
                        IERC20(step.pool).safeIncreaseAllowance(address(this), type(uint256).max);
                    }
                    (, amountsOut, ) = _vault.removeLiquidity(
                        RemoveLiquidityParams({
                            pool: step.pool,
                            from: params.sender,
                            maxBptAmountIn: stepExactAmountIn,
                            minAmountsOut: amountsOut,
                            kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                            userData: params.userData
                        })
                    );

                    if (isLastStep) {
                        // The amount out for the last step of the path should be recorded for the return value, and the
                        // amount for the token should be sent back to the sender later on.
                        pathAmountsOut[i] = amountsOut[tokenIndex];
                        _currentSwapTokensOut.add(address(step.tokenOut));
                        _currentSwapTokenOutAmounts[address(step.tokenOut)] += amountsOut[tokenIndex];
                    } else {
                        // Input for the next step is output of current step.
                        stepExactAmountIn = amountsOut[tokenIndex];
                        // The token in for the next step is the token out of the current step.
                        stepTokenIn = step.tokenOut;
                    }
                } else if (!path.shouldPayFirst && address(step.tokenOut) == step.pool) {
                    // Token out is BPT: add liquidity - Single token exact in (unbalanced)
                    (uint256[] memory exactAmountsIn, ) = _getSingleInputArrayAndTokenIndex(
                        step.pool,
                        stepTokenIn,
                        stepExactAmountIn
                    );

                    (, uint256 bptAmountOut, ) = _vault.addLiquidity(
                        AddLiquidityParams({
                            pool: step.pool,
                            to: params.sender,
                            maxAmountsIn: exactAmountsIn,
                            minBptAmountOut: minAmountOut,
                            kind: AddLiquidityKind.UNBALANCED,
                            userData: params.userData
                        })
                    );

                    if (isLastStep) {
                        // The amount out for the last step of the path should be recorded for the return value.
                        // We do not need to register the amount out in _currentSwapTokenOutAmounts since the BPT
                        // is minted directly to the sender, so this step can be considered settled at this point.
                        pathAmountsOut[i] = bptAmountOut;
                        _currentSwapTokensOut.add(address(step.tokenOut));
                        _settledTokenAmounts[address(step.tokenOut)] += bptAmountOut;
                    } else {
                        // Input for the next step is output of current step.
                        stepExactAmountIn = bptAmountOut;
                        // The token in for the next step is the token out of the current step.
                        stepTokenIn = step.tokenOut;
                        // If this is an intermediate step, we'll need to send it back to the vault
                        // to get credit for the BPT minted in the add liquidity operation.
                        if (params.sender == address(this)) {
                            // Required for queries or in case router holds tokens.
                            IERC20(step.pool).safeTransfer(address(_vault), bptAmountOut);
                        } else {
                            _permit2.transferFrom(params.sender, address(_vault), uint160(bptAmountOut), step.pool);
                        }
                        _vault.settle(IERC20(step.pool));
                    }
                } else {
                    // No BPT involved in the operation: regular swap exact in
                    (, , uint256 amountOut) = _vault.swap(
                        SwapParams({
                            kind: SwapKind.EXACT_IN,
                            pool: step.pool,
                            tokenIn: stepTokenIn,
                            tokenOut: step.tokenOut,
                            amountGivenRaw: stepExactAmountIn,
                            limitRaw: minAmountOut,
                            userData: params.userData
                        })
                    );

                    if (isLastStep) {
                        // The amount out for the last step of the path should be recorded for the return value, and the
                        // amount for the token should be sent back to the sender later on.
                        pathAmountsOut[i] = amountOut;
                        _currentSwapTokensOut.add(address(step.tokenOut));
                        _currentSwapTokenOutAmounts[address(step.tokenOut)] += amountOut;
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
        payable
        nonReentrant
        onlyVault
        returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn)
    {
        // If path has a flag shouldPayFirst, collects the tokens from user before computePath
        // (tokens will be wrapped)
        for (uint256 i = 0; i < params.paths.length; i++) {
            SwapPathExactAmountOut memory path = params.paths[i];

            if (path.shouldPayFirst) {
                _takeTokenIn(params.sender, path.tokenIn, path.maxAmountIn, false);
                _currentSwapTokensOut.add(address(path.tokenIn));
                _currentSwapTokenOutAmounts[address(path.tokenIn)] += path.maxAmountIn;
            }
        }

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
        tokensIn = _currentSwapTokensIn._values; // Copy transient storage to memory
        amountsIn = new uint256[](tokensIn.length);
        for (uint256 i = 0; i < tokensIn.length; ++i) {
            amountsIn[i] = _currentSwapTokenInAmounts[tokensIn[i]] + _settledTokenAmounts[tokensIn[i]];
            _settledTokenAmounts[tokensIn[i]] = 0;
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
            // For example, if all paths share the same token in, the set will end up with only one entry.
            // Since the path is 'given out', the output of the operation specified by the last step in each path will
            // be added to calculate the amounts in for each token.
            // TODO: this should be transient
            _currentSwapTokensIn.add(address(path.tokenIn));

            // Backwards iteration: the exact amount out applies to the last step, so we cannot iterate from first to
            // last. The calculated input of step (j) is the exact amount out for step (j - 1).
            for (int256 j = int256(path.steps.length - 1); j >= 0; --j) {
                SwapPathStep memory step = path.steps[uint256(j)];
                bool isLastStep = (j == 0);

                // These two variables are set at the beginning of the iteration and are used as inputs for
                // the operation described by the step.
                uint256 stepMaxAmountIn;
                IERC20 stepTokenIn;

                // Stack too deep
                {
                    bool isFirstStep = (uint256(j) == path.steps.length - 1);

                    if (isFirstStep) {
                        // The first step in the iteration is the last one in the given array of steps, and it
                        // specifies the output token for the step as well as the exact amount out for that token.
                        // Output amounts are stored to send them later on.
                        // TODO: This should be transient.
                        _currentSwapTokensOut.add(address(step.tokenOut));
                        _currentSwapTokenOutAmounts[address(step.tokenOut)] += stepExactAmountOut;
                    }

                    if (isLastStep) {
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
                }

                if (!path.shouldPayFirst && address(stepTokenIn) == step.pool) {
                    // Token in is BPT: remove liquidity - Single token exact out

                    // Remove liquidity is not transient when it comes to BPT, meaning the caller needs to have the
                    // required amount when performing the operation. In this case, the BPT amount needed for the
                    // operation is not known in advance, so we take a flashloan for all the available reserves.
                    // The last step is the one that defines the inputs for this path. The caller should have enough
                    // BPT to burn already if that's the case, so we just skip this step if so.
                    if (isLastStep == false) {
                        stepMaxAmountIn = _vault.getReservesOf(stepTokenIn);
                        _vault.sendTo(IERC20(step.pool), params.sender, stepMaxAmountIn);
                    }

                    (uint256[] memory exactAmountsOut, ) = _getSingleInputArrayAndTokenIndex(
                        step.pool,
                        step.tokenOut,
                        stepExactAmountOut
                    );

                    if (params.sender == address(this)) {
                        // Needed for queries.
                        // If router is the sender, it has to approve itself.
                        IERC20(step.pool).approve(address(this), type(uint256).max);
                    }
                    (uint256 bptAmountIn, , ) = _vault.removeLiquidity(
                        RemoveLiquidityParams({
                            pool: step.pool,
                            from: params.sender,
                            maxBptAmountIn: stepMaxAmountIn,
                            minAmountsOut: exactAmountsOut,
                            kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                            userData: params.userData
                        })
                    );

                    if (isLastStep) {
                        // BPT is burnt instantly, so we don't need to send it to the Vault during settlement.
                        pathAmountsIn[i] = bptAmountIn;
                        _settledTokenAmounts[address(stepTokenIn)] += bptAmountIn;
                    } else {
                        // Output for the step (j - 1) is the input of step (j).
                        stepExactAmountOut = bptAmountIn;
                        // Refund unused portion of BPT flashloan to the Vault
                        if (bptAmountIn < stepMaxAmountIn) {
                            if (params.sender == address(this)) {
                                // Required for queries or in case router holds tokens.
                                IERC20(stepTokenIn).safeTransfer(address(_vault), stepMaxAmountIn - bptAmountIn);
                            } else {
                                _permit2.transferFrom(
                                    params.sender,
                                    address(_vault),
                                    uint160(stepMaxAmountIn - bptAmountIn),
                                    address(stepTokenIn)
                                );
                            }
                            _vault.settle(IERC20(stepTokenIn));
                        }
                    }
                } else if (!path.shouldPayFirst && address(step.tokenOut) == step.pool) {
                    // Token out is BPT: add liquidity - Single token exact out
                    (uint256[] memory stepAmountsIn, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
                        step.pool,
                        stepTokenIn,
                        stepMaxAmountIn
                    );

                    // Reusing `amountsIn` as input argument and function output to prevent stack too deep error.
                    (stepAmountsIn, , ) = _vault.addLiquidity(
                        AddLiquidityParams({
                            pool: step.pool,
                            to: params.sender,
                            maxAmountsIn: stepAmountsIn,
                            minBptAmountOut: stepExactAmountOut,
                            kind: AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                            userData: params.userData
                        })
                    );

                    if (isLastStep) {
                        // The amount out for the last step of the path should be recorded for the return value.
                        pathAmountsIn[i] = stepAmountsIn[tokenIndex];
                        _currentSwapTokenInAmounts[address(stepTokenIn)] += stepAmountsIn[tokenIndex];
                    } else {
                        stepExactAmountOut = stepAmountsIn[tokenIndex];
                    }

                    // stack-too-deep
                    {
                        // The last step given determines the outputs for the path. Since this is given out, the last
                        // step given is the first one to be executed in the loop.
                        bool isFirstStep = (uint256(j) == path.steps.length - 1);
                        if (isFirstStep) {
                            // Instead of sending tokens back to the vault, we can just discount it from whatever
                            // the vault owes the sender to make one less transfer.
                            _currentSwapTokenOutAmounts[address(step.tokenOut)] -= stepExactAmountOut;
                        } else {
                            if (params.sender == address(this)) {
                                IERC20(step.pool).safeTransfer(address(_vault), stepExactAmountOut);
                            } else {
                                _permit2.transferFrom(
                                    params.sender,
                                    address(_vault),
                                    uint160(stepExactAmountOut),
                                    step.pool
                                );
                            }
                            _vault.settle(IERC20(step.pool));
                        }
                    }
                } else {
                    // No BPT involved in the operation: regular swap exact out
                    (, uint256 amountIn, ) = _vault.swap(
                        SwapParams({
                            kind: SwapKind.EXACT_OUT,
                            pool: step.pool,
                            tokenIn: stepTokenIn,
                            tokenOut: step.tokenOut,
                            amountGivenRaw: stepExactAmountOut,
                            limitRaw: stepMaxAmountIn,
                            userData: params.userData
                        })
                    );

                    if (isLastStep) {
                        pathAmountsIn[i] = amountIn;
                        _currentSwapTokenInAmounts[address(stepTokenIn)] += amountIn;
                    } else {
                        stepExactAmountOut = amountIn;
                    }
                }
            }
        }
    }

    /// @inheritdoc IBatchRouter
    function querySwapExactIn(
        SwapPathExactAmountIn[] memory paths,
        bytes calldata userData
    ) external returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) {
        for (uint256 i = 0; i < paths.length; ++i) {
            paths[i].minAmountOut = 0;
        }

        return
            abi.decode(
                _vault.quote(
                    abi.encodeWithSelector(
                        BatchRouter.querySwapExactInHook.selector,
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

    function querySwapExactInHook(
        SwapExactInHookParams calldata params
    )
        external
        payable
        nonReentrant
        onlyVault
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        (pathAmountsOut, tokensOut, amountsOut) = _swapExactInHook(params);
    }

    /// @inheritdoc IBatchRouter
    function querySwapExactOut(
        SwapPathExactAmountOut[] memory paths,
        bytes calldata userData
    ) external returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) {
        for (uint256 i = 0; i < paths.length; ++i) {
            paths[i].maxAmountIn = _MAX_AMOUNT;
        }

        return
            abi.decode(
                _vault.quote(
                    abi.encodeWithSelector(
                        BatchRouter.querySwapExactOutHook.selector,
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

    function querySwapExactOutHook(
        SwapExactOutHookParams calldata params
    )
        external
        payable
        nonReentrant
        onlyVault
        returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn)
    {
        (pathAmountsIn, tokensIn, amountsIn) = _swapExactOutHook(params);
    }

    function _settlePaths(address sender, bool wethIsEth) internal {
        // numTokensIn / Out may be 0 if the inputs and / or outputs are not transient.
        // For example, a swap starting with a 'remove liquidity' step will already have burned the input tokens,
        // in which case there is nothing to settle. Then, since we're iterating backwards below, we need to be able
        // to subtract 1 from these quantities without reverting, which is why we use signed integers.
        int256 numTokensIn = int256(_currentSwapTokensIn.length());
        uint256 ethAmountIn = 0;

        // Iterate backwards, from the last element to 0 (included).
        // Removing the last element from a set is cheaper than removing the first one.
        for (int256 i = int256(numTokensIn - 1); i >= 0; --i) {
            address tokenIn = _currentSwapTokensIn.unchecked_at(uint256(i));
            if (_currentSwapTokenOutAmounts[tokenIn] > 0) {
                if (_currentSwapTokenOutAmounts[tokenIn] > _currentSwapTokenInAmounts[tokenIn]) {
                    _currentSwapTokenOutAmounts[tokenIn] -= _currentSwapTokenInAmounts[tokenIn];
                } else {
                    _currentSwapTokenInAmounts[tokenIn] -= _currentSwapTokenOutAmounts[tokenIn];
                    _currentSwapTokensOut.remove(tokenIn);
                    _currentSwapTokenOutAmounts[tokenIn] = 0;
                    ethAmountIn += _takeTokenIn(
                        sender,
                        IERC20(tokenIn),
                        _currentSwapTokenInAmounts[tokenIn],
                        wethIsEth
                    );
                }
            } else {
                ethAmountIn += _takeTokenIn(sender, IERC20(tokenIn), _currentSwapTokenInAmounts[tokenIn], wethIsEth);
            }

            _currentSwapTokensIn.remove(tokenIn);
            _currentSwapTokenInAmounts[tokenIn] = 0;
        }

        int256 numTokensOut = int256(_currentSwapTokensOut.length());

        for (int256 i = int256(numTokensOut - 1); i >= 0; --i) {
            address tokenOut = _currentSwapTokensOut.unchecked_at(uint256(i));
            _sendTokenOut(sender, IERC20(tokenOut), _currentSwapTokenOutAmounts[tokenOut], wethIsEth);

            _currentSwapTokensOut.remove(tokenOut);
            _currentSwapTokenOutAmounts[tokenOut] = 0;
        }

        // Return the rest of ETH to sender
        _returnEth(sender, ethAmountIn);
    }
}
