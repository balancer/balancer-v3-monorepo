// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import {
    ICompositeLiquidityRouterErrors
} from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouterErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/RouterTypes.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import {
    TransientEnumerableSet
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/TransientEnumerableSet.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

import { BatchRouterCommon } from "./BatchRouterCommon.sol";

/// @notice Hooks for managing liquidity in composite pools.
contract CompositeLiquidityRouterHooks is BatchRouterCommon {
    using TransientEnumerableSet for TransientEnumerableSet.AddressSet;
    using TransientStorageHelpers for *;

    // Token types for nested pools.
    enum CompositeTokenType {
        ERC20,
        BPT,
        ERC4626
    }

    bool internal immutable _isAggregator;

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2,
        bool isAggregator,
        string memory routerVersion
    ) BatchRouterCommon(vault, weth, permit2, routerVersion) {
        _isAggregator = isAggregator;
    }

    // ERC4626 Pool Hooks

    function addLiquidityERC4626PoolUnbalancedHook(
        AddLiquidityHookParams calldata params,
        bool[] calldata wrapUnderlying
    ) external nonReentrant onlyVault returns (uint256 bptAmountOut) {
        (IERC20[] memory erc4626PoolTokens, uint256 numTokens) = _validateERC4626HookParams(
            params.pool,
            params.maxAmountsIn.length,
            wrapUnderlying.length
        );

        uint256[] memory amountsIn = new uint256[](numTokens);
        bool isStaticCall = EVMCallModeHelpers.isStaticCall();

        for (uint256 i = 0; i < numTokens; ++i) {
            amountsIn[i] = _processTokenInExactIn(
                params,
                isStaticCall,
                address(erc4626PoolTokens[i]),
                params.maxAmountsIn[i],
                wrapUnderlying[i]
            );
        }

        // Add wrapped amounts to the ERC4626 pool.
        (, bptAmountOut, ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: params.pool,
                to: params.sender,
                maxAmountsIn: amountsIn,
                minBptAmountOut: params.minBptAmountOut,
                kind: params.kind,
                userData: params.userData
            })
        );

        // If there's leftover ETH, send it back to the sender. The router should not keep ETH.
        _returnEth(params.sender);
    }

    function addLiquidityERC4626PoolProportionalHook(
        AddLiquidityHookParams calldata params,
        bool[] calldata wrapUnderlying
    ) external nonReentrant onlyVault returns (uint256[] memory amountsIn) {
        (IERC20[] memory erc4626PoolTokens, uint256 numTokens) = _validateERC4626HookParams(
            params.pool,
            params.maxAmountsIn.length,
            wrapUnderlying.length
        );

        uint256[] memory maxAmounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            maxAmounts[i] = _MAX_AMOUNT;
        }

        // Add token amounts to the ERC4626 pool.
        (uint256[] memory actualAmountsIn, , ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: params.pool,
                to: params.sender,
                maxAmountsIn: maxAmounts,
                minBptAmountOut: params.minBptAmountOut,
                kind: params.kind,
                userData: params.userData
            })
        );

        amountsIn = new uint256[](numTokens);
        bool isStaticCall = EVMCallModeHelpers.isStaticCall();

        for (uint256 i = 0; i < numTokens; ++i) {
            amountsIn[i] = _processTokenInExactOut(
                params,
                isStaticCall,
                address(erc4626PoolTokens[i]),
                actualAmountsIn[i],
                wrapUnderlying[i],
                params.maxAmountsIn[i]
            );
        }

        // If there's leftover ETH, send it back to the sender. The router should not keep ETH.
        _returnEth(params.sender);
    }

    function removeLiquidityERC4626PoolProportionalHook(
        RemoveLiquidityHookParams calldata params,
        bool[] calldata unwrapWrapped
    ) external nonReentrant onlyVault returns (uint256[] memory amountsOut) {
        (IERC20[] memory erc4626PoolTokens, uint256 numTokens) = _validateERC4626HookParams(
            params.pool,
            params.minAmountsOut.length,
            unwrapWrapped.length
        );

        (, uint256[] memory actualAmountsOut, ) = _vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: params.pool,
                from: params.sender,
                maxBptAmountIn: params.maxBptAmountIn,
                minAmountsOut: new uint256[](numTokens),
                kind: params.kind,
                userData: params.userData
            })
        );

        amountsOut = new uint256[](numTokens);
        bool isStaticCall = EVMCallModeHelpers.isStaticCall();

        for (uint256 i = 0; i < numTokens; ++i) {
            amountsOut[i] = _processTokenOutExactIn(
                params,
                isStaticCall,
                address(erc4626PoolTokens[i]),
                actualAmountsOut[i],
                unwrapWrapped[i],
                params.minAmountsOut[i]
            );
        }
    }

    // ERC4626 Pool helper functions

    /**
     * @notice Ensure parameters passed to hooks are valid, and return the set of tokens.
     * @param pool The pool address
     * @param amountsLength The length of the token (max) amounts array
     * @param wrapLength The length of the wrap flag array
     * @return poolTokens The pool tokens, sorted in pool registration order
     * @return numTokens The token count
     */
    function _validateERC4626HookParams(
        address pool,
        uint256 amountsLength,
        uint256 wrapLength
    ) private view returns (IERC20[] memory poolTokens, uint256 numTokens) {
        poolTokens = _vault.getPoolTokens(pool);
        numTokens = poolTokens.length;

        InputHelpers.ensureInputLengthMatch(numTokens, amountsLength, wrapLength);
    }

    /**
     * @notice Processes a single token for input during add liquidity operations.
     * @dev Handles wrapping and token transfers when not in a query context.
     * @param liquidityParams Liquidity parameters passed down from the caller
     * @param isStaticCall Flag indicating whether we are in a static context
     * @param token The incoming token
     * @param amountIn The token amount (or max amount)
     * @param needToWrap Flag indicating whether this token is an ERC4626 to be wrapped
     * @return actualAmountIn The final token amount (of the underlying token if wrapped)
     */
    function _processTokenInExactIn(
        AddLiquidityHookParams calldata liquidityParams,
        bool isStaticCall,
        address token,
        uint256 amountIn,
        bool needToWrap
    ) private returns (uint256 actualAmountIn) {
        address settlementToken = needToWrap ? _vault.getERC4626BufferAsset(IERC4626(token)) : token;
        if (needToWrap && settlementToken == address(0)) {
            revert IVaultErrors.BufferNotInitialized(IERC4626(token));
        }

        if (isStaticCall == false) {
            if (_isAggregator) {
                // Settle the prepayment amount that was already sent
                _vault.settle(IERC20(settlementToken), amountIn);
            } else {
                // Retrieve tokens from the sender using Permit2
                _takeTokenIn(liquidityParams.sender, IERC20(settlementToken), amountIn, liquidityParams.wethIsEth);
            }
        }

        if (needToWrap) {
            if (amountIn > 0) {
                (, , actualAmountIn) = _vault.erc4626BufferWrapOrUnwrap(
                    BufferWrapOrUnwrapParams({
                        kind: SwapKind.EXACT_IN,
                        direction: WrappingDirection.WRAP,
                        wrappedToken: IERC4626(token),
                        amountGivenRaw: amountIn,
                        limitRaw: 0
                    })
                );
            }
        } else {
            actualAmountIn = amountIn;
        }
    }

    /**
     * @notice Processes a single token for input during proportional add liquidity operations.
     * @dev Handles wrapping and token transfers when not in a query context.
     * @param liquidityParams Liquidity parameters passed down from the caller
     * @param isStaticCall Flag indicating whether we are in a static context
     * @param token The incoming token
     * @param amountIn The amount of incoming tokens
     * @param needToWrap Flag indicating whether this token is an ERC4626 to be wrapped
     * @param maxAmountIn The final token amount (of the underlying token if wrapped)
     * @return actualAmountIn The final token amount (of the underlying token if wrapped)
     */
    function _processTokenInExactOut(
        AddLiquidityHookParams calldata liquidityParams,
        bool isStaticCall,
        address token,
        uint256 amountIn,
        bool needToWrap,
        uint256 maxAmountIn
    ) private returns (uint256 actualAmountIn) {
        IERC20 settlementToken = needToWrap ? IERC20(_vault.getERC4626BufferAsset(IERC4626(token))) : IERC4626(token);

        if (needToWrap && address(settlementToken) == address(0)) {
            revert IVaultErrors.BufferNotInitialized(IERC4626(token));
        }

        if (isStaticCall == false) {
            if (_isAggregator) {
                // Settle the prepayment amount that was already sent
                _vault.settle(IERC20(settlementToken), maxAmountIn);
            } else {
                // Retrieve tokens from the sender using Permit2
                _takeTokenIn(liquidityParams.sender, settlementToken, maxAmountIn, liquidityParams.wethIsEth);
            }
        }

        if (needToWrap) {
            if (amountIn > 0) {
                // `erc4626BufferWrapOrUnwrap` will fail if the wrappedToken isn't ERC4626-conforming.
                (, actualAmountIn, ) = _vault.erc4626BufferWrapOrUnwrap(
                    BufferWrapOrUnwrapParams({
                        kind: SwapKind.EXACT_OUT,
                        direction: WrappingDirection.WRAP,
                        wrappedToken: IERC4626(token),
                        amountGivenRaw: amountIn,
                        limitRaw: maxAmountIn
                    })
                );
            }
        } else {
            actualAmountIn = amountIn;
        }

        if (actualAmountIn > maxAmountIn) {
            revert IVaultErrors.AmountInAboveMax(settlementToken, amountIn, maxAmountIn);
        }

        if (isStaticCall == false) {
            _sendTokenOut(
                liquidityParams.sender,
                settlementToken,
                maxAmountIn - actualAmountIn,
                liquidityParams.wethIsEth
            );
        }
    }

    /**
     * @notice Processes a single token for output during remove liquidity operations.
     * @dev Handles unwrapping and token transfers when not in a query context.
     * @param liquidityParams Liquidity parameters passed down from the caller
     * @param isStaticCall Flag indicating whether we are in a static context
     * @param token The outgoing token
     * @param amountOut The token amount out
     * @param needToUnwrap Flag indicating whether this token is an ERC4626 to be unwrapped
     * @param minAmountOut The minimum token amountOut
     * @return actualAmountOut The actual amountOut (in underlying token if unwrapped)
     */
    function _processTokenOutExactIn(
        RemoveLiquidityHookParams calldata liquidityParams,
        bool isStaticCall,
        address token,
        uint256 amountOut,
        bool needToUnwrap,
        uint256 minAmountOut
    ) private returns (uint256 actualAmountOut) {
        IERC20 tokenOut;

        if (needToUnwrap) {
            IERC4626 wrappedToken = IERC4626(token);
            IERC20 underlyingToken = IERC20(_vault.getERC4626BufferAsset(wrappedToken));

            tokenOut = underlyingToken;

            if (address(underlyingToken) == address(0)) {
                revert IVaultErrors.BufferNotInitialized(wrappedToken);
            }

            if (amountOut > 0) {
                (, , actualAmountOut) = _vault.erc4626BufferWrapOrUnwrap(
                    BufferWrapOrUnwrapParams({
                        kind: SwapKind.EXACT_IN,
                        direction: WrappingDirection.UNWRAP,
                        wrappedToken: wrappedToken,
                        amountGivenRaw: amountOut,
                        limitRaw: minAmountOut
                    })
                );

                if (isStaticCall == false) {
                    _sendTokenOut(liquidityParams.sender, underlyingToken, actualAmountOut, liquidityParams.wethIsEth);
                }
            }
        } else {
            actualAmountOut = amountOut;
            tokenOut = IERC20(token);

            if (isStaticCall == false) {
                _sendTokenOut(liquidityParams.sender, tokenOut, actualAmountOut, liquidityParams.wethIsEth);
            }
        }

        if (actualAmountOut < minAmountOut) {
            revert IVaultErrors.AmountOutBelowMin(tokenOut, actualAmountOut, minAmountOut);
        }
    }

    /**
     * @notice Centralized handler for ERC4626 unwrapping operations in nested pools.
     * @dev Adds the token and amount to transient storage. Note that the limit is set to 0 here; this is meant to be
     * called mid-operation, and assumes final limits will be checked externally.
     *
     * @param wrappedToken The ERC4626 token to unwrap from
     * @param wrappedAmount Amount of wrapped tokens to unwrap
     */
    function _unwrapExactInAndUpdateTokenOutData(IERC4626 wrappedToken, uint256 wrappedAmount) internal {
        if (wrappedAmount > 0) {
            (, , uint256 underlyingAmount) = _vault.erc4626BufferWrapOrUnwrap(
                BufferWrapOrUnwrapParams({
                    kind: SwapKind.EXACT_IN,
                    direction: WrappingDirection.UNWRAP,
                    wrappedToken: wrappedToken,
                    amountGivenRaw: wrappedAmount,
                    limitRaw: 0
                })
            );

            address underlyingToken = _vault.getERC4626BufferAsset(wrappedToken);
            _currentSwapTokensOut().add(underlyingToken);
            _currentSwapTokenOutAmounts().tAdd(underlyingToken, underlyingAmount);
        }
    }

    // Nested Pool Hooks

    function addLiquidityUnbalancedNestedPoolHook(
        AddLiquidityHookParams calldata params,
        address[] memory tokensIn,
        address[] memory tokensToWrap
    ) external nonReentrant onlyVault returns (uint256 exactBptAmountOut) {
        uint256 numTokensIn = tokensIn.length;

        // Revert if tokensIn length does not match maxAmountsIn length.
        InputHelpers.ensureInputLengthMatch(params.maxAmountsIn.length, numTokensIn);

        // Loads a Set with all amounts to be inserted in the nested pools, so we don't need to iterate over the tokens
        // array to find the child pool amounts to insert.
        for (uint256 i = 0; i < numTokensIn; ++i) {
            uint256 exactAmountIn = params.maxAmountsIn[i];

            if (exactAmountIn == 0) {
                continue;
            }

            address tokenIn = tokensIn[i];

            _currentSwapTokenInAmounts().tSet(tokenIn, exactAmountIn);

            // Ensure there are no duplicate tokens with non-zero amountsIn.
            if (_currentSwapTokensIn().add(tokenIn) == false) {
                revert ICompositeLiquidityRouterErrors.DuplicateTokenIn(tokenIn);
            }
        }

        bool isStaticCall = EVMCallModeHelpers.isStaticCall();

        (uint256[] memory amountsIn, bool parentPoolNeedsLiquidity) = _addLiquidityToParentPool(
            params,
            isStaticCall,
            tokensToWrap
        );

        if (parentPoolNeedsLiquidity) {
            // Adds liquidity to the parent pool, mints parentPool's BPT to the sender, and checks the minimum BPT out.
            (, exactBptAmountOut, ) = _vault.addLiquidity(
                AddLiquidityParams({
                    pool: params.pool,
                    to: isStaticCall ? address(this) : params.sender,
                    maxAmountsIn: amountsIn,
                    minBptAmountOut: params.minBptAmountOut,
                    kind: params.kind,
                    userData: params.userData
                })
            );
        }

        // Settle the amounts in.
        if (isStaticCall == false) {
            _settlePaths(params.sender, params.wethIsEth, _isAggregator);
        }
    }

    function removeLiquidityProportionalNestedPoolHook(
        RemoveLiquidityHookParams calldata params,
        address[] memory tokensOut,
        address[] memory tokensToUnwrap
    ) external nonReentrant onlyVault returns (uint256[] memory amountsOut) {
        IERC20[] memory parentPoolTokens = _vault.getPoolTokens(params.pool);

        InputHelpers.ensureInputLengthMatch(params.minAmountsOut.length, tokensOut.length);

        (, uint256[] memory parentPoolAmountsOut, ) = _vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: params.pool,
                from: params.sender,
                maxBptAmountIn: params.maxBptAmountIn,
                minAmountsOut: new uint256[](parentPoolTokens.length),
                kind: params.kind,
                userData: params.userData
            })
        );

        for (uint256 i = 0; i < parentPoolTokens.length; i++) {
            address parentPoolToken = address(parentPoolTokens[i]);
            uint256 parentPoolAmountOut = parentPoolAmountsOut[i];

            // If the token is an ERC4626 but should not be unwrapped, return ERC20 as the type.
            CompositeTokenType parentPoolTokenType = _computeEffectiveCompositeTokenType(
                parentPoolToken,
                tokensToUnwrap
            );

            if (parentPoolTokenType == CompositeTokenType.BPT) {
                // Token is a BPT, so remove liquidity from the child pool.

                // We don't expect the sender to have BPT to burn. So, we flashloan tokens here (which should in
                // practice just use the existing credit).
                _vault.sendTo(IERC20(parentPoolToken), address(this), parentPoolAmountOut);

                IERC20[] memory childPoolTokens = _vault.getPoolTokens(parentPoolToken);

                // Router is an intermediary in this case. The Vault will burn tokens from the Router, so the Router
                // is both owner and spender (which doesn't need approval).
                (, uint256[] memory childPoolAmountsOut, ) = _vault.removeLiquidity(
                    RemoveLiquidityParams({
                        pool: parentPoolToken,
                        from: address(this),
                        maxBptAmountIn: parentPoolAmountOut,
                        minAmountsOut: new uint256[](childPoolTokens.length),
                        kind: params.kind,
                        userData: params.userData
                    })
                );

                // Return amounts to user.
                for (uint256 j = 0; j < childPoolTokens.length; j++) {
                    address childPoolToken = address(childPoolTokens[j]);
                    uint256 childPoolAmountOut = childPoolAmountsOut[j];

                    // If the token is an ERC4626 but should not be unwrapped, return ERC20 as the type.
                    CompositeTokenType childPoolTokenType = _computeEffectiveCompositeTokenType(
                        childPoolToken,
                        tokensToUnwrap
                    );

                    if (childPoolTokenType == CompositeTokenType.ERC4626) {
                        // Token is an ERC4626 wrapper the user wants to wrap, so unwrap it and return the underlying.
                        _unwrapExactInAndUpdateTokenOutData(IERC4626(childPoolToken), childPoolAmountOut);
                    } else {
                        _currentSwapTokensOut().add(childPoolToken);
                        _currentSwapTokenOutAmounts().tAdd(childPoolToken, childPoolAmountOut);
                    }
                }
            } else if (parentPoolTokenType == CompositeTokenType.ERC4626) {
                // Token is an ERC4626 wrapper that the user wants to unwrap, so unwrap it and return the underlying.
                _unwrapExactInAndUpdateTokenOutData(IERC4626(parentPoolToken), parentPoolAmountOut);
            } else {
                // Token is neither a BPT nor an ERC4626 the user wants to unwrap, so return the amount to the user.
                _currentSwapTokensOut().add(parentPoolToken);
                _currentSwapTokenOutAmounts().tAdd(parentPoolToken, parentPoolAmountOut);
            }
        }

        uint256 numTokensOut = tokensOut.length;

        if (_currentSwapTokensOut().length() != numTokensOut) {
            // If tokensOut length does not match transient tokens out length, the tokensOut array is wrong.
            revert ICompositeLiquidityRouterErrors.WrongTokensOut(_currentSwapTokensOut().values(), tokensOut);
        }

        // The hook writes current swap token and token amounts out.
        amountsOut = new uint256[](numTokensOut);

        bool[] memory checkedTokenIndexes = new bool[](numTokensOut);
        for (uint256 i = 0; i < numTokensOut; ++i) {
            address tokenOut = tokensOut[i];
            uint256 tokenIndex = _currentSwapTokensOut().indexOf(tokenOut);

            if (_currentSwapTokensOut().contains(tokenOut) == false || checkedTokenIndexes[tokenIndex]) {
                // If tokenOut is not in transient tokens out array or token is repeated, the tokensOut array is wrong.
                revert ICompositeLiquidityRouterErrors.WrongTokensOut(_currentSwapTokensOut().values(), tokensOut);
            }

            // Note that the token in the transient array index has already been checked.
            checkedTokenIndexes[tokenIndex] = true;

            amountsOut[i] = _currentSwapTokenOutAmounts().tGet(tokenOut);

            if (amountsOut[i] < params.minAmountsOut[i]) {
                revert IVaultErrors.AmountOutBelowMin(IERC20(tokenOut), amountsOut[i], params.minAmountsOut[i]);
            }
        }

        if (EVMCallModeHelpers.isStaticCall() == false) {
            _settlePaths(params.sender, params.wethIsEth, _isAggregator);
        }
    }

    // Nested Pool helper functions

    // This function factored out to avoid stack-too-deep issues.
    function _addLiquidityToParentPool(
        AddLiquidityHookParams calldata params,
        bool isStaticCall,
        address[] memory tokensToWrap
    ) internal returns (uint256[] memory amountsIn, bool parentPoolNeedsLiquidity) {
        IERC20[] memory parentPoolTokens = _vault.getPoolTokens(params.pool);
        uint256 numParentPoolTokens = parentPoolTokens.length;
        amountsIn = new uint256[](numParentPoolTokens);

        for (uint256 i = 0; i < numParentPoolTokens; i++) {
            address parentPoolToken = address(parentPoolTokens[i]);
            CompositeTokenType parentPoolTokenType = _computeEffectiveCompositeTokenType(parentPoolToken, tokensToWrap);
            uint256 swapAmountIn = _currentSwapTokenInAmounts().tGet(parentPoolToken);

            if (parentPoolTokenType == CompositeTokenType.BPT) {
                swapAmountIn = _addLiquidityToChildPool(params, isStaticCall, parentPoolToken, tokensToWrap);
            } else if (parentPoolTokenType == CompositeTokenType.ERC4626) {
                swapAmountIn = _wrapExactInAndUpdateTokenInData(params, isStaticCall, IERC4626(parentPoolToken));
            } else if (parentPoolTokenType != CompositeTokenType.ERC20) {
                // Should not happen.
                revert IVaultErrors.InvalidTokenType();
            }

            if (swapAmountIn > 0) {
                parentPoolNeedsLiquidity = true;

                amountsIn[i] = swapAmountIn;
                _settledTokenAmounts().tSet(parentPoolToken, swapAmountIn);
            }
        }
    }

    function _addLiquidityToChildPool(
        AddLiquidityHookParams calldata liquidityParams,
        bool isStaticCall,
        address childPool,
        address[] memory tokensToWrap
    ) internal returns (uint256 childBptAmountOut) {
        IERC20[] memory childPoolTokens = _vault.getPoolTokens(childPool);
        uint256 numChildPoolTokens = childPoolTokens.length;
        uint256[] memory childPoolAmountsIn = new uint256[](numChildPoolTokens);
        bool childPoolNeedsLiquidity = false;

        // Process tokens in the child pool (no further nesting allowed).
        for (uint256 i = 0; i < numChildPoolTokens; i++) {
            address childPoolToken = address(childPoolTokens[i]);
            CompositeTokenType childPoolTokenType = _computeEffectiveCompositeTokenType(childPoolToken, tokensToWrap);
            uint256 swapAmountIn = _currentSwapTokenInAmounts().tGet(childPoolToken);
            uint256 childTokenSettledAmount;

            if (swapAmountIn > 0) {
                childTokenSettledAmount = _settledTokenAmounts().tGet(childPoolToken);
            }

            if (childPoolTokenType == CompositeTokenType.ERC4626) {
                swapAmountIn = _wrapExactInAndUpdateTokenInData(
                    liquidityParams,
                    isStaticCall,
                    IERC4626(childPoolToken)
                );
            } else if (childPoolTokenType != CompositeTokenType.ERC20 && childPoolTokenType != CompositeTokenType.BPT) {
                revert IVaultErrors.InvalidTokenType();
            }

            if (swapAmountIn > 0 && childTokenSettledAmount == 0) {
                childPoolNeedsLiquidity = true;

                childPoolAmountsIn[i] = swapAmountIn;
                _settledTokenAmounts().tSet(childPoolToken, swapAmountIn);
            }
        }

        if (childPoolNeedsLiquidity) {
            // Add Liquidity will mint childTokens to the Vault, so the insertion of liquidity in the parent
            // pool will be an accounting adjustment, not a token transfer.
            (, uint256 exactChildBptAmountOut, ) = _vault.addLiquidity(
                AddLiquidityParams({
                    pool: childPool,
                    to: address(_vault),
                    maxAmountsIn: childPoolAmountsIn,
                    minBptAmountOut: 0,
                    kind: liquidityParams.kind,
                    userData: liquidityParams.userData
                })
            );

            childBptAmountOut = exactChildBptAmountOut;

            // Since the BPT will be add to the parent pool, get the credit from the inserted BPT in advance.
            _vault.settle(IERC20(childPool), exactChildBptAmountOut);
        }
    }

    /**
     * @notice Wraps the underlying tokens specified in the transient set `_currentSwapTokenInAmounts`.
     * @dev Afterward, it updates transient storage with the resulting amount of wrapped tokens from the operation.
     * Note that the limit is set to 0 here; this is meant to be called mid-operation, and assumes final limits will
     * be checked externally.
     *
     * @param liquidityParams Liquidity parameters passed down from the caller
     * @param isStaticCall Flag indicating whether we are in a static context
     * @param wrappedToken The token to wrap
     * @return wrappedAmountOut The amountOut of wrapped tokens
     */
    function _wrapExactInAndUpdateTokenInData(
        AddLiquidityHookParams calldata liquidityParams,
        bool isStaticCall,
        IERC4626 wrappedToken
    ) private returns (uint256 wrappedAmountOut) {
        address underlyingToken = _vault.getERC4626BufferAsset(wrappedToken);

        // Get the amountIn of underlying tokens specified by the sender.
        uint256 underlyingAmountIn = _currentSwapTokenInAmounts().tGet(underlyingToken);

        if (underlyingAmountIn > 0) {
            if (isStaticCall == false) {
                if (_isAggregator) {
                    // Settle the prepayment amount that was already sent
                    _vault.settle(IERC20(underlyingToken), underlyingAmountIn);
                } else {
                    // Retrieve tokens from the sender using Permit2
                    _takeTokenIn(
                        liquidityParams.sender,
                        IERC20(underlyingToken),
                        underlyingAmountIn,
                        liquidityParams.wethIsEth
                    );
                }
            }

            (, , wrappedAmountOut) = _vault.erc4626BufferWrapOrUnwrap(
                BufferWrapOrUnwrapParams({
                    kind: SwapKind.EXACT_IN,
                    direction: WrappingDirection.WRAP,
                    wrappedToken: wrappedToken,
                    amountGivenRaw: underlyingAmountIn,
                    limitRaw: 0
                })
            );
        }

        // Remove the underlying token from `_currentSwapTokensIn` and zero out the amount, as these tokens were paid
        // in advance and wrapped. Remaining tokens will be transferred in at the end of the calculation.
        _currentSwapTokensIn().remove(underlyingToken);
        _currentSwapTokenInAmounts().tSet(underlyingToken, 0);
    }

    // Compute the raw token type, and override ERC4626 with ERC20 if it should not be unwrapped.
    function _computeEffectiveCompositeTokenType(
        address token,
        address[] memory tokensToUnwrap
    ) internal view returns (CompositeTokenType tokenType) {
        tokenType = _getCompositeTokenType(token);

        if (tokenType == CompositeTokenType.ERC4626 && _needsWrapOperation(token, tokensToUnwrap) == false) {
            tokenType = CompositeTokenType.ERC20;
        }
    }

    // Determine the token type to direct execution.
    function _getCompositeTokenType(address token) internal view returns (CompositeTokenType tokenType) {
        if (_vault.isPoolRegistered(token)) {
            tokenType = CompositeTokenType.BPT;
        } else if (_vault.isERC4626BufferInitialized(IERC4626(token))) {
            tokenType = CompositeTokenType.ERC4626;
        } else {
            tokenType = CompositeTokenType.ERC20;
        }
    }

    /**
     * @notice Check the current token against the wrap/unwrap set passed in from the user.
     * @dev Linear search is not ideal, and diverges from the flag / transient storage map approach used elsewhere.
     * Unlike with "flat" Boosted Pools, there is no well-defined "token index" into the tree structure (internally,
     * we use pre-order traversal, but this is not part of the interface), so the only way to implement an approach
     * equivalent to Boosted Pools would be to impose a token-ordering requirement on users.
     *
     * Alternatively, we could leave the tokensIn/tokensOut arrays "partial," use a parallel array of wrap/unwrap
     * flags, and figure it out internally (e.g., using transient storage mappings). Since the token list is expected
     * to be short, an optimized linear search should be acceptable.
     *
     * @param token The current nested pool token we are checking
     * @param wrapOperationTokenSet The set of tokens the user has directed the system to wrap/unwrap
     * @return needsWrapOperation The result; true means we should wrap/unwrap; false means treat the token as an ERC20
     */
    function _needsWrapOperation(address token, address[] memory wrapOperationTokenSet) internal pure returns (bool) {
        uint256 numTokens = wrapOperationTokenSet.length;
        for (uint256 i = 0; i < numTokens; ) {
            if (wrapOperationTokenSet[i] == token) {
                return true;
            }

            unchecked {
                ++i;
            }
        }

        return false;
    }
}
