// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IAggregatorBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IAggregatorBatchRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
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
contract AggregatorBatchRouter is IAggregatorBatchRouter, BatchRouterCommon {
    using TransientEnumerableSet for TransientEnumerableSet.AddressSet;
    using TransientStorageHelpers for *;

    /**
     * @notice Not enough tokens sent to cover the operation amount.
     * @param senderCredits Amounts needed to cover the operation
     * @param senderDebits Amounts sent by the sender
     */
    error InsufficientFunds(address token, uint256 senderCredits, uint256 senderDebits);

    /// @notice The operation not supported by the router.
    error OperationNotSupported();

    constructor(
        IVault vault,
        string memory routerVersion
    ) BatchRouterCommon(vault, IWETH(address(0)), IPermit2(address(0)), routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    /// @inheritdoc IAggregatorBatchRouter
    function swapExactIn(
        IBatchRouter.SwapPathExactAmountIn[] memory paths,
        uint256 deadline,
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
                        AggregatorBatchRouter.swapExactInHook,
                        IBatchRouter.SwapExactInHookParams({
                            sender: msg.sender,
                            paths: paths,
                            deadline: deadline,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256[], address[], uint256[])
            );
    }

    /// @inheritdoc IAggregatorBatchRouter
    function swapExactOut(
        IBatchRouter.SwapPathExactAmountOut[] memory paths,
        uint256 deadline,
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
                        AggregatorBatchRouter.swapExactOutHook,
                        IBatchRouter.SwapExactOutHookParams({
                            sender: msg.sender,
                            paths: paths,
                            deadline: deadline,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256[], address[], uint256[])
            );
    }

    function swapExactInHook(
        IBatchRouter.SwapExactInHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        (pathAmountsOut, tokensOut, amountsOut) = _swapExactInHook(params);

        _settlePaths(params.sender, false);
    }

    function _swapExactInHook(
        IBatchRouter.SwapExactInHookParams calldata params
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
            amountsOut[i] = _currentSwapTokenOutAmounts().tGet(tokensOut[i]);
        }
    }

    function _computePathAmountsOut(
        IBatchRouter.SwapExactInHookParams calldata params
    ) internal returns (uint256[] memory pathAmountsOut) {
        pathAmountsOut = new uint256[](params.paths.length);

        // Because tokens may repeat, we need to aggregate the total input amount and
        // perform a settlement to prevent overflow.
        if (EVMCallModeHelpers.isStaticCall() == false) {
            // Register the token amounts expected to be paid by the sender upfront as settled
            for (uint256 i = 0; i < params.paths.length; ++i) {
                IBatchRouter.SwapPathExactAmountIn memory path = params.paths[i];
                _currentSwapTokensIn().add(address(path.tokenIn));
                _currentSwapTokenInAmounts().tAdd(address(path.tokenIn), path.exactAmountIn);
            }

            address[] memory tokensIn = _currentSwapTokensIn().values();
            for (uint256 i = 0; i < tokensIn.length; ++i) {
                address tokenIn = tokensIn[i];

                uint256 amount = _currentSwapTokenInAmounts().tGet(tokenIn);
                uint256 tokenInCredit = _vault.settle(IERC20(tokenIn), amount);
                if (tokenInCredit < amount) {
                    revert InsufficientFunds(tokenIn, tokenInCredit, amount);
                }

                _currentSwapTokenInAmounts().tSet(tokenIn, 0);
            }
        }

        for (uint256 i = 0; i < params.paths.length; ++i) {
            IBatchRouter.SwapPathExactAmountIn memory path = params.paths[i];

            // These two variables shall be updated at the end of each step to be used as inputs of the next one.
            // The initial values are the given token and amount in for the current path.
            uint256 stepExactAmountIn = path.exactAmountIn;
            IERC20 stepTokenIn = path.tokenIn;

            for (uint256 j = 0; j < path.steps.length; ++j) {
                SwapStepLocals memory stepLocals;
                stepLocals.isLastStep = (j == path.steps.length - 1);
                stepLocals.isFirstStep = (j == 0);
                uint256 minAmountOut;
                uint256 amountOut;

                // minAmountOut only applies to the last step.
                if (stepLocals.isLastStep) {
                    minAmountOut = path.minAmountOut;
                } else {
                    minAmountOut = 0;
                }

                IBatchRouter.SwapPathStep memory step = path.steps[j];

                if (step.isBuffer) {
                    (, , amountOut) = _vault.erc4626BufferWrapOrUnwrap(
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
                } else if (step.pool != address(stepTokenIn) && step.pool != address(step.tokenOut)) {
                    // No BPT involved in the operation: regular swap exact in.
                    (, , amountOut) = _vault.swap(
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
                } else {
                    revert OperationNotSupported();
                }

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

    function swapExactOutHook(
        IBatchRouter.SwapExactOutHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn)
    {
        (pathAmountsIn, tokensIn, amountsIn) = _swapExactOutHook(params);

        _settlePaths(params.sender, false);
    }

    function _swapExactOutHook(
        IBatchRouter.SwapExactOutHookParams calldata params
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
            address tokenIn = tokensIn[i];
            amountsIn[i] = _currentSwapTokenInAmounts().tGet(tokenIn);
            _currentSwapTokenInAmounts().tSet(tokenIn, 0);
        }
    }

    /**
     * @dev Executes every swap path in the given input parameters.
     * Computes inputs for the path, and aggregates them by token and amounts as well in transient storage.
     */
    function _computePathAmountsIn(
        IBatchRouter.SwapExactOutHookParams calldata params
    ) internal returns (uint256[] memory pathAmountsIn) {
        for (uint256 i = 0; i < params.paths.length; ++i) {
            // Register the token amounts expected to be paid by the sender upfront as settled
            IBatchRouter.SwapPathExactAmountOut memory path = params.paths[i];
            _currentSwapTokensIn().add(address(path.tokenIn));
            _currentSwapTokenInAmounts().tAdd(address(path.tokenIn), path.maxAmountIn);
        }

        address[] memory tokensIn = _currentSwapTokensIn().values();
        for (uint256 i = 0; i < tokensIn.length; ++i) {
            address tokenIn = tokensIn[i];
            uint256 amount = _currentSwapTokenInAmounts().tGet(tokenIn);

            if (EVMCallModeHelpers.isStaticCall() == false) {
                uint256 tokenInCredit = _vault.settle(IERC20(tokenIn), amount);
                if (tokenInCredit < amount) {
                    revert InsufficientFunds(tokenIn, tokenInCredit, amount);
                }
            }

            _currentSwapTokenInAmounts().tSet(tokenIn, 0);
        }

        pathAmountsIn = new uint256[](params.paths.length);
        for (uint256 i = 0; i < params.paths.length; ++i) {
            IBatchRouter.SwapPathExactAmountOut memory path = params.paths[i];
            // This variable shall be updated at the end of each step to be used as input of the next one.
            // The first value corresponds to the given amount out for the current path.
            uint256 stepExactAmountOut = path.exactAmountOut;

            // Backwards iteration: the exact amount out applies to the last step, so we cannot iterate from first to
            // last. The calculated input of step (j) is the exact amount out for step (j - 1).
            for (int256 j = int256(path.steps.length - 1); j >= 0; --j) {
                IBatchRouter.SwapPathStep memory step = path.steps[uint256(j)];
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

                uint256 amountIn;
                if (step.isBuffer) {
                    (, amountIn, ) = _vault.erc4626BufferWrapOrUnwrap(
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
                } else if (step.pool != address(stepTokenIn) && step.pool != address(step.tokenOut)) {
                    // No BPT involved in the operation: regular swap exact out.
                    (, amountIn, ) = _vault.swap(
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
                } else {
                    revert OperationNotSupported();
                }

                if (stepLocals.isLastStep) {
                    // Save the remaining difference between maxAmountIn and actualAmountIn,
                    // and add it to the token out amounts for processing during settlement.
                    pathAmountsIn[i] = amountIn;
                    _currentSwapTokensOut().add(address(stepTokenIn));
                    _currentSwapTokenOutAmounts().tAdd(address(stepTokenIn), path.maxAmountIn - amountIn);

                    _currentSwapTokenInAmounts().tAdd(address(path.tokenIn), amountIn);
                } else {
                    stepExactAmountOut = amountIn;
                }
            }
        }
    }

    function permitBatchAndCall(
        PermitApproval[] calldata,
        bytes[] calldata,
        IAllowanceTransfer.PermitBatch calldata,
        bytes calldata,
        bytes[] calldata
    ) external payable override returns (bytes[] memory) {
        revert OperationNotSupported();
    }

    function multicall(bytes[] calldata) public payable override returns (bytes[] memory) {
        revert OperationNotSupported();
    }

    /***************************************************************************
                                     Queries
    ***************************************************************************/

    /// @inheritdoc IAggregatorBatchRouter
    function querySwapExactIn(
        IBatchRouter.SwapPathExactAmountIn[] memory paths,
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
                        AggregatorBatchRouter.querySwapExactInHook,
                        IBatchRouter.SwapExactInHookParams({
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

    /// @inheritdoc IAggregatorBatchRouter
    function querySwapExactOut(
        IBatchRouter.SwapPathExactAmountOut[] memory paths,
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
                        AggregatorBatchRouter.querySwapExactOutHook,
                        IBatchRouter.SwapExactOutHookParams({
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
        IBatchRouter.SwapExactInHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        (pathAmountsOut, tokensOut, amountsOut) = _swapExactInHook(params);
    }

    function querySwapExactOutHook(
        IBatchRouter.SwapExactOutHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn)
    {
        (pathAmountsIn, tokensIn, amountsIn) = _swapExactOutHook(params);
    }
}
