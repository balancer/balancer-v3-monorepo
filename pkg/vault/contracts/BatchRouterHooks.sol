// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/BatchRouterTypes.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import {
    TransientEnumerableSet
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/TransientEnumerableSet.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

import { BatchRouterCommon } from "./BatchRouterCommon.sol";

/**
 * @notice Entrypoint for batch swaps, and batch swap queries.
 * @dev The external API functions unlock the Vault, which calls back into the corresponding hook functions.
 * These interpret the steps and paths in the input data, perform token accounting (in transient storage, to save gas),
 * settle with the Vault, and handle wrapping and unwrapping ETH.
 */
abstract contract BatchRouterHooks is BatchRouterCommon {
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
                                    Swaps Exact In
    ***************************************************************************/

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
    )
        internal
        virtual
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
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
            uint256 settledAmount = _settledTokenAmounts().tGet(tokensOut[i]);
            amountsOut[i] = _currentSwapTokenOutAmounts().tGet(tokensOut[i]) + settledAmount;

            if (settledAmount != 0) {
                _settledTokenAmounts().tSet(tokensOut[i], 0);
            }
        }
    }

    function _computePathAmountsOut(
        SwapExactInHookParams calldata params
    ) internal virtual returns (uint256[] memory pathAmountsOut) {
        pathAmountsOut = new uint256[](params.paths.length);

        if (_isPrepaid) {
            _prepayIfNeededExactIn(params);
        }

        for (uint256 i = 0; i < params.paths.length; ++i) {
            SwapPathExactAmountIn memory path = params.paths[i];

            // These two variables shall be updated at the end of each step to be used as inputs of the next one.
            // The initial values are the given token and amount in for the current path.
            uint256 stepExactAmountIn = path.exactAmountIn;
            IERC20 stepTokenIn = path.tokenIn;

            if (_isPrepaid == false) {
                if (path.steps[0].isBuffer && EVMCallModeHelpers.isStaticCall() == false) {
                    // If first step is a buffer, take the token in advance. We need this to wrap/unwrap.
                    _takeTokenIn(params.sender, stepTokenIn, stepExactAmountIn, params.wethIsEth);
                } else {
                    // Paths may (or may not) share the same token in. To minimize token transfers,
                    // we store the addresses in a set with unique addresses that can be iterated later on.
                    // For example, if all paths share the same token in, the set will end up with only one entry.
                    _currentSwapTokensIn().add(address(stepTokenIn));
                    _currentSwapTokenInAmounts().tAdd(address(stepTokenIn), stepExactAmountIn);
                }
            }

            for (uint256 j = 0; j < path.steps.length; ++j) {
                bool isLastStep = (j == path.steps.length - 1);
                bool isFirstStep = (j == 0);

                // minAmountOut only applies to the last step.
                uint256 minAmountOut = isLastStep ? path.minAmountOut : 0;

                uint256 amountOut;
                SwapPathStep memory step = path.steps[j];

                if (step.isBuffer) {
                    amountOut = _erc4626BufferWrapOrUnwrapExactIn(
                        step.pool,
                        stepTokenIn,
                        step.tokenOut,
                        stepExactAmountIn,
                        minAmountOut,
                        isLastStep
                    );
                } else if (address(stepTokenIn) == step.pool) {
                    // TODO: remove this restriction, adjust `_removeLiquidityExactIn` accordingly.
                    _ensureNotPrepaid();

                    amountOut = _removeLiquidityExactIn(
                        params.userData,
                        params.sender,
                        step.pool,
                        stepTokenIn,
                        step.tokenOut,
                        stepExactAmountIn,
                        minAmountOut,
                        isFirstStep,
                        isLastStep
                    );
                } else if (address(step.tokenOut) == step.pool) {
                    // TODO: remove this restriction, adjust `_addLiquidityExactIn` accordingly.
                    _ensureNotPrepaid();

                    amountOut = _addLiquidityExactIn(
                        params.userData,
                        params.sender,
                        step.pool,
                        stepTokenIn,
                        step.tokenOut,
                        stepExactAmountIn,
                        minAmountOut,
                        isLastStep
                    );
                } else {
                    amountOut = _swapExactIn(
                        params.userData,
                        step.pool,
                        stepTokenIn,
                        step.tokenOut,
                        stepExactAmountIn,
                        minAmountOut,
                        isLastStep
                    );
                }

                if (isLastStep) {
                    // The amount out for the last step of the path should be recorded for the return value, and the
                    // amount for the token should be sent back to the sender later on.
                    pathAmountsOut[i] = amountOut;
                } else {
                    // Input for the next step is the output of the current step.
                    stepExactAmountIn = amountOut;
                    // The tokenIn for the next step is the tokenOut of the current step.
                    stepTokenIn = step.tokenOut;
                }
            }
        }
    }

    function _erc4626BufferWrapOrUnwrapExactIn(
        address pool,
        IERC20 stepTokenIn,
        IERC20 stepTokenOut,
        uint256 stepExactAmountIn,
        uint256 minAmountOut,
        bool isLastStep
    ) internal returns (uint256 amountOut) {
        (, , amountOut) = _vault.erc4626BufferWrapOrUnwrap(
            BufferWrapOrUnwrapParams({
                kind: SwapKind.EXACT_IN,
                direction: pool == address(stepTokenIn) ? WrappingDirection.UNWRAP : WrappingDirection.WRAP,
                wrappedToken: IERC4626(pool),
                amountGivenRaw: stepExactAmountIn,
                limitRaw: minAmountOut
            })
        );

        if (isLastStep) {
            _updateSwapTokensOut(address(stepTokenOut), amountOut);
        }
    }

    function _removeLiquidityExactIn(
        bytes memory userData,
        address sender,
        address pool,
        IERC20 stepTokenIn,
        IERC20 stepTokenOut,
        uint256 stepExactAmountIn,
        uint256 minAmountOut,
        bool isFirstStep,
        bool isLastStep
    ) internal returns (uint256 amountOut) {
        // Token in is BPT: remove liquidity - Single token exact in

        // Remove liquidity is not transient for BPT, meaning the caller needs to have the required amount
        // when performing the operation. These tokens might be the output of a previous step, in which case
        // the user will have a BPT credit.
        if (isFirstStep) {
            if (stepExactAmountIn > 0 && sender != address(this)) {
                // If this is the first step, the sender must have the tokens. Therefore, we can transfer
                // them to the Router, which acts as an intermediary. If the sender is the Router, we just
                // skip this step (useful for queries).
                //
                // This saves one permit(1) approval for the BPT to the Router; if we burned tokens
                // directly from the sender we would need their approval.
                _permit2.transferFrom(sender, address(this), stepExactAmountIn.toUint160(), address(stepTokenIn));
            }

            // BPT is burned instantly, so we don't need to send it back later.
            if (_currentSwapTokenInAmounts().tGet(address(stepTokenIn)) > 0) {
                _currentSwapTokenInAmounts().tSub(address(stepTokenIn), stepExactAmountIn);
            }
        } else {
            // If this is an intermediate step, we don't expect the sender to have BPT to burn.
            // So, we flashloan tokens here (which should in practice just use existing credit).
            _vault.sendTo(IERC20(pool), address(this), stepExactAmountIn);
        }

        // minAmountOut cannot be 0 in this case, as that would send an array of 0s to the Vault, which
        // wouldn't know which token to use.
        (uint256[] memory amountsOut, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
            pool,
            stepTokenOut,
            minAmountOut == 0 ? 1 : minAmountOut
        );

        // The Router is always an intermediary in this case. The Vault will burn tokens from the Router, so
        // the Router is both owner and spender, which doesn't require approval.
        // Reusing `amountsOut` as input argument and function output to prevent stack too deep error.
        (, amountsOut, ) = _vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool,
                from: address(this),
                maxBptAmountIn: stepExactAmountIn,
                minAmountsOut: amountsOut,
                kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                userData: userData
            })
        );

        amountOut = amountsOut[tokenIndex];

        if (isLastStep) {
            _updateSwapTokensOut(address(stepTokenOut), amountOut);
        }
    }

    function _addLiquidityExactIn(
        bytes memory userData,
        address sender,
        address pool,
        IERC20 stepTokenIn,
        IERC20 stepTokenOut,
        uint256 stepExactAmountIn,
        uint256 minAmountOut,
        bool isLastStep
    ) internal returns (uint256 amountOut) {
        // Token out is BPT: add liquidity - Single token exact in (unbalanced).
        (uint256[] memory exactAmountsIn, ) = _getSingleInputArrayAndTokenIndex(pool, stepTokenIn, stepExactAmountIn);

        (, uint256 bptAmountOut, ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: isLastStep ? sender : address(_vault),
                maxAmountsIn: exactAmountsIn,
                minBptAmountOut: minAmountOut,
                kind: AddLiquidityKind.UNBALANCED,
                userData: userData
            })
        );

        if (isLastStep) {
            address tokenOut = address(stepTokenOut);
            _currentSwapTokensOut().add(tokenOut);
            _settledTokenAmounts().tAdd(tokenOut, bptAmountOut);
        } else {
            _vault.settle(IERC20(pool), bptAmountOut);
        }

        return bptAmountOut;
    }

    function _swapExactIn(
        bytes memory userData,
        address pool,
        IERC20 stepTokenIn,
        IERC20 stepTokenOut,
        uint256 stepExactAmountIn,
        uint256 minAmountOut,
        bool isLastStep
    ) internal returns (uint256 amountOut) {
        // No BPT involved in the operation: regular swap exact in.
        (, , amountOut) = _vault.swap(
            VaultSwapParams({
                kind: SwapKind.EXACT_IN,
                pool: pool,
                tokenIn: stepTokenIn,
                tokenOut: stepTokenOut,
                amountGivenRaw: stepExactAmountIn,
                limitRaw: minAmountOut,
                userData: userData
            })
        );

        if (isLastStep) {
            _updateSwapTokensOut(address(stepTokenOut), amountOut);
        }
    }

    /***************************************************************************
                                    Swaps Exact Out
    ***************************************************************************/

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
    ) internal virtual returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) {
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
            uint256 settledAmount = _settledTokenAmounts().tGet(tokenIn);
            amountsIn[i] = _currentSwapTokenInAmounts().tGet(tokenIn) + settledAmount;

            if (settledAmount != 0) {
                _settledTokenAmounts().tSet(tokenIn, 0);
            }

            if (_isPrepaid) {
                _currentSwapTokenInAmounts().tSet(tokenIn, 0);
            }
        }
    }

    /**
     * @dev Executes every swap path in the given input parameters.
     * Computes inputs for the path, and aggregates them by token and amounts as well in transient storage.
     */
    function _computePathAmountsIn(
        SwapExactOutHookParams calldata params
    ) internal virtual returns (uint256[] memory pathAmountsIn) {
        pathAmountsIn = new uint256[](params.paths.length);

        if (_isPrepaid) {
            _prepayIfNeededExactOut(params);
        }

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

                bool isLastStep = (j == 0);
                bool isFirstStep = (uint256(j) == path.steps.length - 1);

                if (isFirstStep) {
                    // The first step in the iteration is the last one in the given array of steps, and it
                    // specifies the output token for the step as well as the exact amount out for that token.
                    // Output amounts are stored to send them later on.
                    _updateSwapTokensOut(address(step.tokenOut), stepExactAmountOut);
                }

                // These two variables are set at the beginning of the iteration and are used as inputs for
                // the operation described by the step.
                uint256 stepMaxAmountIn;
                IERC20 stepTokenIn;

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

                uint256 amountIn;

                if (step.isBuffer) {
                    amountIn = _erc4626BufferWrapOrUnwrapExactOut(
                        params.sender,
                        params.wethIsEth,
                        step.pool,
                        path.tokenIn,
                        stepTokenIn,
                        stepExactAmountOut,
                        path.maxAmountIn,
                        stepMaxAmountIn,
                        isLastStep
                    );
                } else if (address(stepTokenIn) == step.pool) {
                    // TODO: remove this restriction, adjust `_removeLiquidityExactOut` accordingly.
                    _ensureNotPrepaid();

                    amountIn = _removeLiquidityExactOut(
                        params.userData,
                        params.sender,
                        step.pool,
                        stepTokenIn,
                        stepExactAmountOut,
                        stepMaxAmountIn,
                        step.tokenOut,
                        isLastStep
                    );
                } else if (address(step.tokenOut) == step.pool) {
                    // TODO: remove this restriction, adjust `_addLiquidityExactOut` accordingly.
                    _ensureNotPrepaid();

                    amountIn = _addLiquidityExactOut(
                        params.userData,
                        params.sender,
                        step.pool,
                        stepTokenIn,
                        step.tokenOut,
                        stepExactAmountOut,
                        stepMaxAmountIn,
                        isFirstStep,
                        isLastStep
                    );
                } else {
                    amountIn = _swapExactOut(
                        params.userData,
                        step.pool,
                        stepTokenIn,
                        step.tokenOut,
                        stepExactAmountOut,
                        stepMaxAmountIn,
                        path.maxAmountIn,
                        isLastStep
                    );
                }

                if (isLastStep) {
                    pathAmountsIn[i] = amountIn;
                } else {
                    stepExactAmountOut = amountIn;
                }
            }
        }
    }

    function _erc4626BufferWrapOrUnwrapExactOut(
        address sender,
        bool wethIsEth,
        address pool,
        IERC20 pathTokenIn,
        IERC20 stepTokenIn,
        uint256 exactAmountOut,
        uint256 pathMaxAmountIn,
        uint256 maxAmountIn,
        bool isLastStep
    ) internal returns (uint256 amountIn) {
        if (_isPrepaid == false && isLastStep && EVMCallModeHelpers.isStaticCall() == false) {
            // The buffer will need this token to wrap/unwrap, so take it from the user in advance.
            _takeTokenIn(sender, stepTokenIn, pathMaxAmountIn, wethIsEth);
        }

        (, amountIn, ) = _vault.erc4626BufferWrapOrUnwrap(
            BufferWrapOrUnwrapParams({
                kind: SwapKind.EXACT_OUT,
                direction: pool == address(stepTokenIn) ? WrappingDirection.UNWRAP : WrappingDirection.WRAP,
                wrappedToken: IERC4626(pool),
                amountGivenRaw: exactAmountOut,
                limitRaw: maxAmountIn
            })
        );

        if (isLastStep) {
            if (_isPrepaid) {
                _currentSwapTokenInAmounts().tAdd(address(pathTokenIn), amountIn);
            } else {
                _settledTokenAmounts().tAdd(address(pathTokenIn), amountIn);
            }
            // Since the token was taken in advance, returns to the user what is left from the
            // wrap/unwrap operation.
            _updateSwapTokensOut(address(stepTokenIn), maxAmountIn - amountIn);
        }
    }

    function _removeLiquidityExactOut(
        bytes memory userData,
        address sender,
        address pool,
        IERC20 stepTokenIn,
        uint256 stepExactAmountOut,
        uint256 stepMaxAmountIn,
        IERC20 tokenOut,
        bool isLastStep
    ) internal returns (uint256 amountIn) {
        // Token in is BPT: remove liquidity - Single token exact out

        // Remove liquidity is not transient for BPT, meaning the caller needs to have the required amount when
        // performing the operation. In this case, the BPT amount needed for the operation is not known in advance,
        // so we take a flashloan for all the available reserves.
        //
        // The last step is the one that defines the inputs for this path. The caller should have enough
        // BPT to burn already if that's the case, so we just skip this step if so.
        if (isLastStep == false) {
            stepMaxAmountIn = _vault.getReservesOf(stepTokenIn);
            _vault.sendTo(IERC20(pool), address(this), stepMaxAmountIn);
        } else if (sender != address(this)) {
            // The last step being executed is the first step in the swap path, meaning that it's the one
            // that defines the inputs of the path.
            //
            // In that case, the sender must have the tokens. Therefore, we can transfer them
            // to the Router, which acts as an intermediary. If the sender is the Router, we just skip this
            // step (useful for queries).
            _permit2.transferFrom(sender, address(this), stepMaxAmountIn.toUint160(), address(stepTokenIn));
        }

        (uint256[] memory exactAmountsOut, ) = _getSingleInputArrayAndTokenIndex(pool, tokenOut, stepExactAmountOut);

        // The Router is always an intermediary in this case. The Vault will burn tokens from the Router, so
        // the Router is both owner and spender, which doesn't require approval.
        (amountIn, , ) = _vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool,
                from: address(this),
                maxBptAmountIn: stepMaxAmountIn,
                minAmountsOut: exactAmountsOut,
                kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                userData: userData
            })
        );

        if (isLastStep) {
            _settledTokenAmounts().tAdd(address(stepTokenIn), amountIn);

            // Refund unused portion of BPT to the user.
            if (amountIn < stepMaxAmountIn && sender != address(this)) {
                stepTokenIn.safeTransfer(address(sender), stepMaxAmountIn - amountIn);
            }
        } else {
            // First or intermediate steps
            if (amountIn < stepMaxAmountIn) {
                // Refund unused portion of BPT flashloan to the Vault.
                uint256 refundAmount = stepMaxAmountIn - amountIn;
                stepTokenIn.safeTransfer(address(_vault), refundAmount);
                _vault.settle(stepTokenIn, refundAmount);
            }
        }
    }

    function _addLiquidityExactOut(
        bytes memory userData,
        address sender,
        address pool,
        IERC20 stepTokenIn,
        IERC20 tokenOut,
        uint256 stepExactAmountOut,
        uint256 stepMaxAmountIn,
        bool isFirstStep,
        bool isLastStep
    ) internal returns (uint256 amountIn) {
        // Token out is BPT: add liquidity - Single token exact out.
        (uint256[] memory stepAmountsIn, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
            pool,
            stepTokenIn,
            stepMaxAmountIn
        );

        // Reusing `amountsIn` as input argument and function output to prevent stack too deep error.
        (stepAmountsIn, , ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: isFirstStep ? sender : address(_vault),
                maxAmountsIn: stepAmountsIn,
                minBptAmountOut: stepExactAmountOut,
                kind: AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                userData: userData
            })
        );

        amountIn = stepAmountsIn[tokenIndex];

        uint256 stepSettlementAmount = isLastStep ? stepExactAmountOut : amountIn;

        // The first step executed determines the outputs for the path, since this is given out.
        if (isFirstStep) {
            // Instead of sending tokens back to the Vault, we can just discount it from whatever
            // the Vault owes the sender to make one less transfer.
            _currentSwapTokenOutAmounts().tSub(address(tokenOut), stepSettlementAmount);
        } else {
            // If it's not the first step, BPT is minted to the Vault so we just get the credit.
            _vault.settle(IERC20(pool), stepSettlementAmount);
        }

        if (isLastStep) {
            _currentSwapTokenInAmounts().tAdd(address(stepTokenIn), amountIn);
        }
    }

    function _swapExactOut(
        bytes memory userData,
        address pool,
        IERC20 stepTokenIn,
        IERC20 stepTokenOut,
        uint256 stepExactAmountOut,
        uint256 stepMaxAmountIn,
        uint256 pathMaxAmountIn,
        bool isLastStep
    ) internal returns (uint256 amountIn) {
        // No BPT involved in the operation: regular swap exact out.
        (, amountIn, ) = _vault.swap(
            VaultSwapParams({
                kind: SwapKind.EXACT_OUT,
                pool: pool,
                tokenIn: stepTokenIn,
                tokenOut: stepTokenOut,
                amountGivenRaw: stepExactAmountOut,
                limitRaw: stepMaxAmountIn,
                userData: userData
            })
        );

        if (isLastStep) {
            _currentSwapTokenInAmounts().tAdd(address(stepTokenIn), amountIn);

            if (_isPrepaid) {
                _updateSwapTokensOut(address(stepTokenIn), pathMaxAmountIn - amountIn);
            }
        }
    }

    /***************************************************************************
                                     Queries
    ***************************************************************************/

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

    /***************************************************************************
                                     Other
    ***************************************************************************/

    function _ensureNotPrepaid() internal view {
        if (_isPrepaid) {
            revert OperationNotSupported();
        }
    }

    function _prepayIfNeededExactIn(SwapExactInHookParams calldata params) internal {
        // Register the token amounts expected to be paid by the sender upfront as settled
        for (uint256 i = 0; i < params.paths.length; ++i) {
            SwapPathExactAmountIn memory path = params.paths[i];
            _currentSwapTokensIn().add(address(path.tokenIn));
            _currentSwapTokenInAmounts().tAdd(address(path.tokenIn), path.exactAmountIn);
        }

        address[] memory tokensIn = _currentSwapTokensIn().values();
        for (uint256 i = 0; i < tokensIn.length; ++i) {
            address tokenIn = tokensIn[i];
            uint256 amount = _currentSwapTokenInAmounts().tGet(tokenIn);

            _takeOrSettle(params.sender, params.wethIsEth, tokenIn, amount);
            _currentSwapTokenInAmounts().tSet(tokenIn, 0);
        }
    }

    function _prepayIfNeededExactOut(SwapExactOutHookParams calldata params) internal {
        for (uint256 i = 0; i < params.paths.length; ++i) {
            // Register the token amounts expected to be paid by the sender upfront as settled
            SwapPathExactAmountOut memory path = params.paths[i];
            _currentSwapTokensIn().add(address(path.tokenIn));
            _currentSwapTokenInAmounts().tAdd(address(path.tokenIn), path.maxAmountIn);
        }

        address[] memory tokensIn = _currentSwapTokensIn().values();
        for (uint256 i = 0; i < tokensIn.length; ++i) {
            address tokenIn = tokensIn[i];
            uint256 amount = _currentSwapTokenInAmounts().tGet(tokenIn);

            _takeOrSettle(params.sender, params.wethIsEth, tokenIn, amount);
            _currentSwapTokenInAmounts().tSet(tokenIn, 0);
        }
    }
}
