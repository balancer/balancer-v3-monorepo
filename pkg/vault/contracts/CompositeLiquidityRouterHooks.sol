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
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

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

    // Factor out common parameters used in internal liquidity functions.
    struct RouterCallParams {
        address sender;
        bool wethIsEth;
        bool isStaticCall;
    }

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

        RouterCallParams memory callParams = _buildRouterCallParams(params.sender, params.wethIsEth);
        uint256[] memory amountsIn = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            amountsIn[i] = _processTokenInExactIn(
                address(erc4626PoolTokens[i]),
                params.maxAmountsIn[i],
                wrapUnderlying[i],
                callParams
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

        RouterCallParams memory callParams = _buildRouterCallParams(params.sender, params.wethIsEth);
        amountsIn = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            amountsIn[i] = _processTokenInExactOut(
                address(erc4626PoolTokens[i]),
                actualAmountsIn[i],
                wrapUnderlying[i],
                params.maxAmountsIn[i],
                callParams
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

        RouterCallParams memory callParams = _buildRouterCallParams(params.sender, params.wethIsEth);
        amountsOut = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            amountsOut[i] = _processTokenOutExactIn(
                address(erc4626PoolTokens[i]),
                actualAmountsOut[i],
                unwrapWrapped[i],
                params.minAmountsOut[i],
                callParams
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
     * @param token The incoming token
     * @param amountIn The token amount (or max amount)
     * @param needToWrap Flag indicating whether this token is an ERC4626 to be wrapped
     * @param callParams Common parameters from the main router call
     * @return actualAmountIn The final token amount (of the underlying token if wrapped)
     */
    function _processTokenInExactIn(
        address token,
        uint256 amountIn,
        bool needToWrap,
        RouterCallParams memory callParams
    ) private returns (uint256 actualAmountIn) {
        if (needToWrap) {
            IERC4626 wrappedToken = IERC4626(token);
            address underlyingToken = _vault.getERC4626BufferAsset(wrappedToken);

            if (underlyingToken == address(0)) {
                revert IVaultErrors.BufferNotInitialized(wrappedToken);
            }

            if (amountIn > 0) {
                if (callParams.isStaticCall == false) {
                    _takeTokenIn(callParams.sender, IERC20(underlyingToken), amountIn, callParams.wethIsEth);
                }

                (, , actualAmountIn) = _vault.erc4626BufferWrapOrUnwrap(
                    BufferWrapOrUnwrapParams({
                        kind: SwapKind.EXACT_IN,
                        direction: WrappingDirection.WRAP,
                        wrappedToken: wrappedToken,
                        amountGivenRaw: amountIn,
                        limitRaw: 0
                    })
                );
            }
        } else {
            actualAmountIn = amountIn;

            if (callParams.isStaticCall == false) {
                _takeTokenIn(callParams.sender, IERC20(token), amountIn, callParams.wethIsEth);
            }
        }
    }

    /**
     * @notice Processes a single token for input during proportional add liquidity operations.
     * @dev Handles wrapping and token transfers when not in a query context.
     * @param token The incoming token
     * @param amountIn The amount of incoming tokens
     * @param needToWrap Flag indicating whether this token is an ERC4626 to be wrapped
     * @param maxAmountIn The final token amount (of the underlying token if wrapped)
     * @param callParams Common parameters from the main router call
     * @return actualAmountIn The final token amount (of the underlying token if wrapped)
     */
    function _processTokenInExactOut(
        address token,
        uint256 amountIn,
        bool needToWrap,
        uint256 maxAmountIn,
        RouterCallParams memory callParams
    ) private returns (uint256 actualAmountIn) {
        IERC20 tokenIn;

        if (needToWrap) {
            IERC4626 wrappedToken = IERC4626(token);
            IERC20 underlyingToken = IERC20(_vault.getERC4626BufferAsset(wrappedToken));
            tokenIn = underlyingToken;

            if (address(underlyingToken) == address(0)) {
                revert IVaultErrors.BufferNotInitialized(wrappedToken);
            }

            if (amountIn > 0) {
                if (callParams.isStaticCall == false) {
                    _takeTokenIn(callParams.sender, underlyingToken, maxAmountIn, callParams.wethIsEth);
                }

                // `erc4626BufferWrapOrUnwrap` will fail if the wrappedToken isn't ERC4626-conforming.
                (, actualAmountIn, ) = _vault.erc4626BufferWrapOrUnwrap(
                    BufferWrapOrUnwrapParams({
                        kind: SwapKind.EXACT_OUT,
                        direction: WrappingDirection.WRAP,
                        wrappedToken: wrappedToken,
                        amountGivenRaw: amountIn,
                        limitRaw: maxAmountIn
                    })
                );
            }

            if (callParams.isStaticCall == false) {
                // The maxAmountsIn of underlying tokens was taken from the user, so the difference between
                // `maxAmountsIn` and the exact underlying amount needs to be returned to the sender.
                _sendTokenOut(callParams.sender, underlyingToken, maxAmountIn - actualAmountIn, callParams.wethIsEth);
            }
        } else {
            actualAmountIn = amountIn;
            tokenIn = IERC20(token);

            if (callParams.isStaticCall == false) {
                _takeTokenIn(callParams.sender, tokenIn, actualAmountIn, callParams.wethIsEth);
            }
        }

        if (actualAmountIn > maxAmountIn) {
            revert IVaultErrors.AmountInAboveMax(tokenIn, amountIn, maxAmountIn);
        }
    }

    /**
     * @notice Processes a single token for output during remove liquidity operations.
     * @dev Handles unwrapping and token transfers when not in a query context.
     * @param token The outgoing token
     * @param amountOut The token amount out
     * @param needToUnwrap Flag indicating whether this token is an ERC4626 to be unwrapped
     * @param minAmountOut The minimum token amountOut
     * @param callParams Common parameters from the main router call
     * @return actualAmountOut The actual amountOut (in underlying token if unwrapped)
     */
    function _processTokenOutExactIn(
        address token,
        uint256 amountOut,
        bool needToUnwrap,
        uint256 minAmountOut,
        RouterCallParams memory callParams
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

                if (callParams.isStaticCall == false) {
                    _sendTokenOut(callParams.sender, underlyingToken, actualAmountOut, callParams.wethIsEth);
                }
            }
        } else {
            actualAmountOut = amountOut;
            tokenOut = IERC20(token);

            if (callParams.isStaticCall == false) {
                _sendTokenOut(callParams.sender, tokenOut, actualAmountOut, callParams.wethIsEth);
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

    /**
     * @notice Creates RouterCallParams struct with common parameters
     * @param sender The sender address
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @return callParams The constructed RouterCallParams
     */
    function _buildRouterCallParams(
        address sender,
        bool wethIsEth
    ) private view returns (RouterCallParams memory callParams) {
        callParams = RouterCallParams({
            sender: sender,
            wethIsEth: wethIsEth,
            isStaticCall: EVMCallModeHelpers.isStaticCall()
        });
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
            uint256 maxAmountIn = params.maxAmountsIn[i];

            if (maxAmountIn == 0) {
                continue;
            }

            address tokenIn = tokensIn[i];

            _currentSwapTokenInAmounts().tSet(tokenIn, maxAmountIn);

            // Ensure there are no duplicate tokens with non-zero amountsIn.
            if (_currentSwapTokensIn().add(tokenIn) == false) {
                revert ICompositeLiquidityRouterErrors.DuplicateTokenIn(tokenIn);
            }
        }

        (uint256[] memory amountsIn, bool parentPoolNeedsLiquidity) = _addLiquidityToParentPool(params, tokensToWrap);

        bool isStaticCall = EVMCallModeHelpers.isStaticCall();

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
            _settlePaths(params.sender, params.wethIsEth);
        }
    }

    // This function factored out to avoid stack-too-deep issues.
    function _addLiquidityToParentPool(
        AddLiquidityHookParams calldata params,
        address[] memory tokensToWrap
    ) internal returns (uint256[] memory amountsIn, bool parentPoolNeedsLiquidity) {
        RouterCallParams memory callParams = _buildRouterCallParams(params.sender, params.wethIsEth);
        IERC20[] memory parentPoolTokens = _vault.getPoolTokens(params.pool);
        uint256 numParentPoolTokens = parentPoolTokens.length;
        amountsIn = new uint256[](numParentPoolTokens);

        for (uint256 i = 0; i < numParentPoolTokens; i++) {
            address parentPoolToken = address(parentPoolTokens[i]);
            CompositeTokenType tokenType = _getCompositeTokenType(parentPoolToken);
            uint256 swapAmountIn = _currentSwapTokenInAmounts().tGet(parentPoolToken);

            if (tokenType == CompositeTokenType.BPT) {
                swapAmountIn = _addLiquidityToChildPool(parentPoolToken, tokensToWrap, params, callParams);
            } else if (tokenType == CompositeTokenType.ERC4626) {
                if (
                    swapAmountIn == 0 &&
                    _currentSwapTokenInAmounts().tGet(_vault.getERC4626BufferAsset(IERC4626(parentPoolToken))) > 0
                ) {
                    swapAmountIn = _wrapExactInAndUpdateTokenInData(IERC4626(parentPoolToken), callParams);
                }
            } else if (tokenType != CompositeTokenType.ERC20) {
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

            CompositeTokenType parentPoolTokenType = _getCompositeTokenType(parentPoolToken);

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

                    CompositeTokenType childPoolTokenType = _getCompositeTokenType(childPoolToken);
                    if (
                        childPoolTokenType == CompositeTokenType.ERC4626 &&
                        _needsWrapOperation(childPoolToken, tokensToUnwrap)
                    ) {
                        // Token is an ERC4626 wrapper, so unwrap it and return the underlying.
                        _unwrapExactInAndUpdateTokenOutData(IERC4626(childPoolToken), childPoolAmountOut);
                    } else {
                        _currentSwapTokensOut().add(childPoolToken);
                        _currentSwapTokenOutAmounts().tAdd(childPoolToken, childPoolAmountOut);
                    }
                }
            } else if (
                parentPoolTokenType == CompositeTokenType.ERC4626 &&
                _needsWrapOperation(parentPoolToken, tokensToUnwrap)
            ) {
                // Token is an ERC4626 wrapper, so unwrap it and return the underlying.
                _unwrapExactInAndUpdateTokenOutData(IERC4626(parentPoolToken), parentPoolAmountOut);
            } else {
                // Token is neither a BPT nor ERC4626, so return the amount to the user.
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
            _settlePaths(params.sender, params.wethIsEth);
        }
    }

    // Nested Pool helper functions

    function _addLiquidityToChildPool(
        address childPool,
        address[] memory tokensToWrap,
        AddLiquidityHookParams calldata liquidityParams,
        RouterCallParams memory callParams
    ) internal returns (uint256 childBptAmountOut) {
        IERC20[] memory childPoolTokens = _vault.getPoolTokens(childPool);
        uint256 numChildPoolTokens = childPoolTokens.length;

        uint256[] memory childPoolAmountsIn = new uint256[](numChildPoolTokens);
        bool childPoolNeedsLiquidity;

        // Process tokens in the child pool (no further nesting allowed).
        for (uint256 i = 0; i < numChildPoolTokens; i++) {
            address childPoolToken = address(childPoolTokens[i]);
            CompositeTokenType childPoolTokenType = _getCompositeTokenType(childPoolToken);
            uint256 swapAmountIn = _currentSwapTokenInAmounts().tGet(childPoolToken);
            uint256 childTokenSettledAmount;

            if (swapAmountIn > 0) {
                childTokenSettledAmount = _settledTokenAmounts().tGet(childPoolToken);
            }

            if (childPoolTokenType == CompositeTokenType.ERC4626) {
                if (swapAmountIn == 0 && _needsWrapOperation(childPoolToken, tokensToWrap)) {
                    // If it's a wrapped token, and it's not in `_currentSwapTokenInAmounts`, we need to wrap it.
                    swapAmountIn = _wrapExactInAndUpdateTokenInData(IERC4626(childPoolToken), callParams);
                }
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
     * @param wrappedToken The token to wrap
     * @param callParams The router call parameters (sender, static, and weth flag)
     * @return wrappedAmountOut The amountOut of wrapped tokens
     */
    function _wrapExactInAndUpdateTokenInData(
        IERC4626 wrappedToken,
        RouterCallParams memory callParams
    ) private returns (uint256 wrappedAmountOut) {
        address underlyingToken = _vault.getERC4626BufferAsset(wrappedToken);

        // Get the amountIn of underlying tokens specified by the sender.
        uint256 underlyingAmountIn = _currentSwapTokenInAmounts().tGet(underlyingToken);

        if (underlyingAmountIn > 0) {
            if (callParams.isStaticCall == false) {
                _takeTokenIn(callParams.sender, IERC20(underlyingToken), underlyingAmountIn, callParams.wethIsEth);
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

    // Check the current token against the wrap
    function _needsWrapOperation(address token, address[] memory wrappedTokens) internal pure returns (bool) {
        uint256 numTokens = wrappedTokens.length;
        for (uint256 i = 0; i < numTokens; ) {
            if (wrappedTokens[i] == token) {
                return true;
            }

            unchecked {
                ++i;
            }
        }

        return false;
    }
}
