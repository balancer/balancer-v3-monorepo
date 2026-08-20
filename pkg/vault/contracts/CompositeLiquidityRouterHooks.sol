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
import { RevertCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/RevertCodec.sol";
import {
    TransientEnumerableSet
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/TransientEnumerableSet.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

import { BatchRouterCommon } from "./BatchRouterCommon.sol";

/// @notice Hooks for managing liquidity in composite pools.
abstract contract CompositeLiquidityRouterHooks is BatchRouterCommon {
    using TransientEnumerableSet for TransientEnumerableSet.AddressSet;
    using TransientStorageHelpers for *;

    // Token types for nested pools.
    enum CompositeTokenType {
        ERC20,
        BPT,
        ERC4626
    }

    // Used to keep track of input tokens that have already been processed in nested pools. This is distinct from
    // `_currentSwapTokensIn`, which keeps track of the input tokens in a batch swap / liquidity operation (e.g.,
    // preventing duplicate inputs like [USDC, DAI, USDC].
    //
    // `_processedTokensIn` guarantees that the unique tokens in [USDC, DAI] are not duplicated during nested pool
    // traversal (e.g., parent and child pools both contain DAI).
    //
    // solhint-disable-next-line var-name-mixedcase
    bytes32 private immutable _PROCESSED_TOKENS_IN_SLOT = _calculateBatchRouterStorageSlot("processedTokensIn");

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2,
        string memory routerVersion
    ) BatchRouterCommon(vault, weth, permit2, routerVersion) {
        // solhint-disable-previous-line no-empty-blocks
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
        (, bptAmountOut, ) = _vault.addLiquidity(_buildAddLiquidityParams(params, amountsIn, params.sender));

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
            _buildAddLiquidityParams(params, maxAmounts, params.sender)
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
            _buildRemoveLiquidityParams(params, numTokens)
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

        _returnEth(params.sender);
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
     * @notice Helper for constructing AddLiquidityParams.
     * @param hookParams Parameters passed down from the hook
     * @param maxAmountsIn Calculated amountsIn
     * @param sender Address of the sender, which is not necessarily that specified in the hookParams
     * @return params AddLiquidityParams struct
     */
    function _buildAddLiquidityParams(
        AddLiquidityHookParams calldata hookParams,
        uint256[] memory maxAmountsIn,
        address sender
    ) internal pure returns (AddLiquidityParams memory) {
        return
            AddLiquidityParams({
                pool: hookParams.pool,
                to: sender,
                maxAmountsIn: maxAmountsIn,
                minBptAmountOut: hookParams.minBptAmountOut,
                kind: hookParams.kind,
                userData: hookParams.userData
            });
    }

    /**
     * @notice Helper for constructing RemoveLiquidityParams.
     * @param hookParams Parameters passed down from the hook
     * @param numTokens Number of tokens (used to construct minAmountsOut array of zeros)
     * @return params RemoveLiquidityParams struct
     */
    function _buildRemoveLiquidityParams(
        RemoveLiquidityHookParams calldata hookParams,
        uint256 numTokens
    ) internal pure returns (RemoveLiquidityParams memory) {
        return
            RemoveLiquidityParams({
                pool: hookParams.pool,
                from: hookParams.sender,
                maxBptAmountIn: hookParams.maxBptAmountIn,
                minAmountsOut: new uint256[](numTokens),
                kind: hookParams.kind,
                userData: hookParams.userData
            });
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
            _takeOrSettle(liquidityParams.sender, liquidityParams.wethIsEth, settlementToken, amountIn);
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
            _takeOrSettle(liquidityParams.sender, liquidityParams.wethIsEth, address(settlementToken), maxAmountIn);
        }

        // If amountIn is 0, actualAmountIn remains at its initialized value of 0.
        if (amountIn > 0) {
            if (needToWrap) {
                // `erc4626BufferWrapOrUnwrap` will fail if the wrappedToken isn't ERC4626-conforming.
                (actualAmountIn, ) = _bufferWrapOrUnwrapPoolAmount(
                    BufferWrapOrUnwrapParams({
                        kind: SwapKind.EXACT_OUT,
                        direction: WrappingDirection.WRAP,
                        wrappedToken: IERC4626(token),
                        amountGivenRaw: amountIn,
                        limitRaw: maxAmountIn
                    })
                );
            } else {
                actualAmountIn = amountIn;
            }
        }

        if (actualAmountIn > maxAmountIn) {
            revert IVaultErrors.AmountInAboveMax(settlementToken, actualAmountIn, maxAmountIn);
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
                // The amount unwrapped here is the pool's, not the caller's: it is this token's share of the burned
                // BPT. The caller asked for the underlying token, and delivering the wrapped token in its place would
                // return an asset they did not ask for, so an amount the buffer will not unwrap fails the operation.
                //
                // The buffer gets no limit of its own. `minAmountOut` is checked at the end of this function, where
                // the error names the token; handing it over here would preempt the Vault's own check on the
                // underlying amount, and report a limit where the real reason is the buffer's minimum.
                (, actualAmountOut) = _bufferWrapOrUnwrapPoolAmount(
                    BufferWrapOrUnwrapParams({
                        kind: SwapKind.EXACT_IN,
                        direction: WrappingDirection.UNWRAP,
                        wrappedToken: wrappedToken,
                        amountGivenRaw: amountOut,
                        limitRaw: 0
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
     * called mid-operation, and assumes final limits will be checked externally. A zero amount registers the
     * underlying token with a zero amount, without calling the buffer. Callers reach this only for tokens whose
     * buffer is initialized (the effective token type requires one), so `getERC4626BufferAsset` cannot return the
     * zero address here.
     *
     * @param wrappedToken The ERC4626 token to unwrap from
     * @param wrappedAmount Amount of wrapped tokens to unwrap
     */
    function _unwrapExactInAndUpdateTokenOutData(IERC4626 wrappedToken, uint256 wrappedAmount) internal {
        uint256 underlyingAmount;

        // The Vault's minimum wrap amount has no zero exemption, so handing the buffer a zero amount would revert
        // the whole nested operation. Nothing needs to be handed over: a zero amount creates no delta, so there is
        // no credit left to settle. This matches the flat ERC4626 path, which also skips the call at zero.
        if (wrappedAmount > 0) {
            // As on the flat path, the amount is the pool's rather than the caller's, and the caller asked for the
            // underlying token, so an amount the buffer will not unwrap fails the whole traversal.
            (, underlyingAmount) = _bufferWrapOrUnwrapPoolAmount(
                BufferWrapOrUnwrapParams({
                    kind: SwapKind.EXACT_IN,
                    direction: WrappingDirection.UNWRAP,
                    wrappedToken: wrappedToken,
                    amountGivenRaw: wrappedAmount,
                    limitRaw: 0
                })
            );
        }

        // Register the token unconditionally. The caller declares the output tokens up front, and the set produced
        // by the traversal must match that declaration exactly, so a token that produced nothing is still an output
        // token: returning early here instead would revert `WrongTokensOut`.
        _updateSwapTokensOut(_vault.getERC4626BufferAsset(wrappedToken), underlyingAmount);
    }

    /**
     * @notice Wraps or unwraps through the Vault buffer, where the amount comes from a pool and not from the caller.
     * @dev Proportional operations fix the amount of each token from the pool's own balances, so the caller cannot
     * choose it: on a removal it is that token's share of the burned pool tokens, and on an addition it is what the
     * pool requires for the pool tokens requested. The Vault refuses wrap and unwrap amounts below its minimum wrap
     * amount, applying that minimum both to the amount it is given and to the amount it calculates, so the smallest
     * amount it will accept is a property of the wrapper: it moves with the wrapper's rate, and it is not the same in
     * the two directions. This router does not predict it. It hands the amount over, and reports the Vault's own
     * verdict in terms of the operation the caller asked for, naming the wrapped token and the amount the pool fixed,
     * where the Vault's error names the token alone. Every other failure means something else, and is bubbled up
     * unchanged, with one mechanical exception: revert data too short to carry a selector (empty included, which is
     * also what an out-of-gas sub-call produces) is reported as `RevertCodec.ErrorSelectorNotFound`.
     *
     * The two buffer calls in this contract that wrap an amount the caller named do not use this, and should not: an
     * amount the caller chose is not one this router should describe as the pool's. Callers pass a nonzero
     * `amountGivenRaw`, denominated in the wrapped token, which is what both errors name: a zero is skipped at the
     * call sites rather than handed over here, and a call site whose given amount were the underlying would need
     * different reporting.
     *
     * @param params The buffer operation, whose `amountGivenRaw` is the pool-derived amount of the wrapped token
     * @return amountInRaw The amount taken in: underlying when wrapping, wrapped when unwrapping
     * @return amountOutRaw The amount produced: wrapped when wrapping, underlying when unwrapping
     */
    function _bufferWrapOrUnwrapPoolAmount(
        BufferWrapOrUnwrapParams memory params
    ) private returns (uint256 amountInRaw, uint256 amountOutRaw) {
        try _vault.erc4626BufferWrapOrUnwrap(params) returns (uint256, uint256 amountIn, uint256 amountOut) {
            (amountInRaw, amountOutRaw) = (amountIn, amountOut);
        } catch (bytes memory returnData) {
            if (RevertCodec.parseSelector(returnData) == IVaultErrors.WrapAmountTooSmall.selector) {
                if (params.direction == WrappingDirection.WRAP) {
                    revert ICompositeLiquidityRouterErrors.RequiredWrapAmountTooSmall(
                        address(params.wrappedToken),
                        params.amountGivenRaw
                    );
                }

                revert ICompositeLiquidityRouterErrors.UnwrapAmountTooSmall(
                    address(params.wrappedToken),
                    params.amountGivenRaw
                );
            }

            // Every other failure means something else, so it is not this router's to reinterpret.
            RevertCodec.bubbleUpRevert(returnData);
        }
    }

    // Nested Pool Hooks

    function addLiquidityUnbalancedNestedPoolHook(
        AddLiquidityHookParams calldata params,
        address[] memory tokensIn,
        address[] memory tokensToWrap
    ) external nonReentrant onlyVault returns (uint256 exactBptAmountOut) {
        InputHelpers.ensureInputLengthMatch(params.maxAmountsIn.length, tokensIn.length);

        // Clear any stale processed token flags from previous operations (e.g., from a query call).
        // This ensures each operation starts with a clean state, so that one tx may contain multiple CLR operations.
        address[] memory processedTokens = _processedTokensIn().values();
        for (uint256 i = processedTokens.length; i > 0; --i) {
            _processedTokensIn().remove(processedTokens[i - 1]);
        }

        // Loads a Set with all amounts to be inserted in the nested pools, so we don't need to iterate over the tokens
        // array to find the child pool amounts to insert.
        for (uint256 i = 0; i < tokensIn.length; ++i) {
            uint256 exactAmountIn = params.maxAmountsIn[i];

            if (exactAmountIn > 0) {
                address tokenIn = tokensIn[i];

                _currentSwapTokenInAmounts().tSet(tokenIn, exactAmountIn);

                // Ensure there are no duplicate tokens with non-zero amountsIn.
                if (_currentSwapTokensIn().add(tokenIn) == false) {
                    revert ICompositeLiquidityRouterErrors.DuplicateTokenIn(tokenIn);
                }
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
                _buildAddLiquidityParams(params, amountsIn, isStaticCall ? address(this) : params.sender)
            );
        }

        if (isStaticCall == false) {
            // Settle the amounts in.
            _settlePaths(params.sender, params.wethIsEth);
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
            _buildRemoveLiquidityParams(params, parentPoolTokens.length)
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
                        // Token is an ERC4626 wrapper the user wants to wrap; unwrap it and return the underlying.
                        _unwrapExactInAndUpdateTokenOutData(IERC4626(childPoolToken), childPoolAmountOut);
                    } else {
                        _updateSwapTokensOut(childPoolToken, childPoolAmountOut);
                    }
                }
            } else if (parentPoolTokenType == CompositeTokenType.ERC4626) {
                // Token is an ERC4626 wrapper that the user wants to unwrap, so unwrap it and return the underlying.
                _unwrapExactInAndUpdateTokenOutData(IERC4626(parentPoolToken), parentPoolAmountOut);
            } else {
                // Token is neither a BPT nor an ERC4626 the user wants to unwrap, so return the amount to the user.
                _updateSwapTokensOut(parentPoolToken, parentPoolAmountOut);
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
            // `indexOf` will revert if tokenOut is not in `_currentSwapTokensOut`.
            uint256 tokenIndex = _currentSwapTokensOut().indexOf(tokenOut);

            if (checkedTokenIndexes[tokenIndex]) {
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
            _settlePaths(params.sender, params.wethIsEth);
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
                // Should not happen. Future-proofing against later addition of token types.
                revert IVaultErrors.InvalidTokenType();
            }

            if (swapAmountIn > 0) {
                parentPoolNeedsLiquidity = true;

                amountsIn[i] = swapAmountIn;
                _processedTokensIn().add(parentPoolToken);
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

            if (childPoolTokenType == CompositeTokenType.ERC4626) {
                swapAmountIn = _wrapExactInAndUpdateTokenInData(
                    liquidityParams,
                    isStaticCall,
                    IERC4626(childPoolToken)
                );
            } else if (childPoolTokenType != CompositeTokenType.ERC20 && childPoolTokenType != CompositeTokenType.BPT) {
                // Should not happen. Future-proofing against later addition of token types.
                revert IVaultErrors.InvalidTokenType();
            }

            if (swapAmountIn > 0) {
                // Ensure this token was not already processed at a different level of the pool hierarchy.
                if (_processedTokensIn().contains(childPoolToken)) {
                    revert ICompositeLiquidityRouterErrors.DuplicateTokenIn(childPoolToken);
                }

                childPoolNeedsLiquidity = true;

                childPoolAmountsIn[i] = swapAmountIn;
                _processedTokensIn().add(childPoolToken);
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
                _takeOrSettle(liquidityParams.sender, liquidityParams.wethIsEth, underlyingToken, underlyingAmountIn);
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
        if (_vault.isPoolRegistered(token)) {
            tokenType = CompositeTokenType.BPT;
        } else if (_vault.isERC4626BufferInitialized(IERC4626(token))) {
            tokenType = _needsWrapOperation(token, tokensToUnwrap)
                ? CompositeTokenType.ERC4626
                : CompositeTokenType.ERC20;
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

    // solhint-disable no-inline-assembly
    function _processedTokensIn() internal view returns (TransientEnumerableSet.AddressSet storage enumerableSet) {
        bytes32 slot = _PROCESSED_TOKENS_IN_SLOT;
        assembly ("memory-safe") {
            enumerableSet.slot := slot
        }
    }
}
