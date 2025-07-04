// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { ICompositeLiquidityRouter } from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouter.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
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

/**
 * @notice Entrypoint for add/remove liquidity operations on ERC4626 and nested pools.
 * @dev The external API functions unlock the Vault, which calls back into the corresponding hook functions.
 * These execute the steps needed to add to and remove liquidity from these special types of pools, and settle
 * the operation with the Vault.
 */
contract CompositeLiquidityRouter is ICompositeLiquidityRouter, BatchRouterCommon {
    using TransientEnumerableSet for TransientEnumerableSet.AddressSet;
    using TransientStorageHelpers for *;

    // Token types for nested pools.
    enum CompositeTokenType {
        ERC20,
        BPT,
        ERC4626
    }

    // Factor out common parameters used for adding liquidity.
    struct CompositeTokenInfo {
        address token;
        CompositeTokenType tokenType;
        uint256 amount;
        bool needToWrap;
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

    /*******************************************************************************
                                ERC4626 Pools
    *******************************************************************************/

    /// @inheritdoc ICompositeLiquidityRouter
    function addLiquidityUnbalancedToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256 bptAmountOut) {
        bptAmountOut = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    CompositeLiquidityRouter.addLiquidityERC4626PoolUnbalancedHook,
                    (
                        AddLiquidityHookParams({
                            sender: msg.sender,
                            pool: pool,
                            maxAmountsIn: exactAmountsIn,
                            minBptAmountOut: minBptAmountOut,
                            kind: AddLiquidityKind.UNBALANCED,
                            wethIsEth: wethIsEth,
                            userData: userData
                        }),
                        wrapUnderlying
                    )
                )
            ),
            (uint256)
        );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function addLiquidityProportionalToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (address[] memory tokensIn, uint256[] memory amountsIn) {
        (tokensIn, amountsIn) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    CompositeLiquidityRouter.addLiquidityERC4626PoolProportionalHook,
                    (
                        AddLiquidityHookParams({
                            sender: msg.sender,
                            pool: pool,
                            maxAmountsIn: maxAmountsIn,
                            minBptAmountOut: exactBptAmountOut,
                            kind: AddLiquidityKind.PROPORTIONAL,
                            wethIsEth: wethIsEth,
                            userData: userData
                        }),
                        wrapUnderlying
                    )
                )
            ),
            (address[], uint256[])
        );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function removeLiquidityProportionalFromERC4626Pool(
        address pool,
        bool[] memory unwrapWrapped,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (address[] memory tokensOut, uint256[] memory amountsOut) {
        (tokensOut, amountsOut) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    CompositeLiquidityRouter.removeLiquidityERC4626PoolProportionalHook,
                    (
                        RemoveLiquidityHookParams({
                            sender: msg.sender,
                            pool: pool,
                            minAmountsOut: minAmountsOut,
                            maxBptAmountIn: exactBptAmountIn,
                            kind: RemoveLiquidityKind.PROPORTIONAL,
                            wethIsEth: wethIsEth,
                            userData: userData
                        }),
                        unwrapWrapped
                    )
                )
            ),
            (address[], uint256[])
        );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function queryAddLiquidityUnbalancedToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory exactAmountsIn,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256 bptAmountOut) {
        AddLiquidityHookParams memory params = _buildQueryAddLiquidityParams(
            pool,
            exactAmountsIn,
            0,
            AddLiquidityKind.UNBALANCED,
            userData
        );

        bptAmountOut = abi.decode(
            _vault.quote(
                abi.encodeCall(CompositeLiquidityRouter.addLiquidityERC4626PoolUnbalancedHook, (params, wrapUnderlying))
            ),
            (uint256)
        );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function queryAddLiquidityProportionalToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (address[] memory tokensIn, uint256[] memory amountsIn) {
        AddLiquidityHookParams memory params = _buildQueryAddLiquidityParams(
            pool,
            new uint256[](0),
            exactBptAmountOut,
            AddLiquidityKind.PROPORTIONAL,
            userData
        );

        (tokensIn, amountsIn) = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    CompositeLiquidityRouter.addLiquidityERC4626PoolProportionalHook,
                    (params, wrapUnderlying)
                )
            ),
            (address[], uint256[])
        );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function queryRemoveLiquidityProportionalFromERC4626Pool(
        address pool,
        bool[] memory unwrapWrapped,
        uint256 exactBptAmountIn,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (address[] memory tokensOut, uint256[] memory amountsOut) {
        IERC20[] memory erc4626PoolTokens = _vault.getPoolTokens(pool);
        RemoveLiquidityHookParams memory params = _buildQueryRemoveLiquidityParams(
            pool,
            exactBptAmountIn,
            erc4626PoolTokens.length,
            userData
        );

        (tokensOut, amountsOut) = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    CompositeLiquidityRouter.removeLiquidityERC4626PoolProportionalHook,
                    (params, unwrapWrapped)
                )
            ),
            (address[], uint256[])
        );
    }

    // ERC4626 Pool Hooks

    function addLiquidityERC4626PoolUnbalancedHook(
        AddLiquidityHookParams calldata params,
        bool[] calldata wrapUnderlying
    ) external nonReentrant onlyVault returns (uint256 bptAmountOut) {
        (IERC20[] memory erc4626PoolTokens, uint256 numTokens) = _validateHookParams(
            params.pool,
            params.maxAmountsIn.length,
            wrapUnderlying.length
        );

        RouterCallParams memory callParams = RouterCallParams({
            sender: params.sender,
            wethIsEth: params.wethIsEth,
            isStaticCall: EVMCallModeHelpers.isStaticCall()
        });

        uint256[] memory amountsIn = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            if (params.maxAmountsIn[i] > 0) {
                amountsIn[i] = _processTokenIn(
                    address(erc4626PoolTokens[i]),
                    params.maxAmountsIn[i],
                    wrapUnderlying[i],
                    callParams
                );
            }
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
    ) external nonReentrant onlyVault returns (address[] memory tokensIn, uint256[] memory amountsIn) {
        (IERC20[] memory erc4626PoolTokens, uint256 numTokens) = _validateHookParams(
            params.pool,
            params.maxAmountsIn.length,
            wrapUnderlying.length
        );

        uint256[] memory maxAmounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            maxAmounts[i] = _MAX_AMOUNT;
        }

        // Add wrapped amounts to the ERC4626 pool.
        (uint256[] memory wrappedAmountsIn, , ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: params.pool,
                to: params.sender,
                maxAmountsIn: maxAmounts,
                minBptAmountOut: params.minBptAmountOut,
                kind: params.kind,
                userData: params.userData
            })
        );

        RouterCallParams memory callParams = RouterCallParams({
            sender: params.sender,
            wethIsEth: params.wethIsEth,
            isStaticCall: EVMCallModeHelpers.isStaticCall()
        });

        tokensIn = new address[](numTokens);
        amountsIn = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            (tokensIn[i], amountsIn[i]) = _processTokenInExactOut(
                address(erc4626PoolTokens[i]),
                wrappedAmountsIn[i],
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
    ) external nonReentrant onlyVault returns (address[] memory tokensOut, uint256[] memory amountsOut) {
        (IERC20[] memory erc4626PoolTokens, uint256 numTokens) = _validateHookParams(
            params.pool,
            params.minAmountsOut.length,
            unwrapWrapped.length
        );

        (, uint256[] memory wrappedAmountsOut, ) = _vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: params.pool,
                from: params.sender,
                maxBptAmountIn: params.maxBptAmountIn,
                minAmountsOut: new uint256[](numTokens),
                kind: params.kind,
                userData: params.userData
            })
        );

        RouterCallParams memory callParams = RouterCallParams({
            sender: params.sender,
            wethIsEth: params.wethIsEth,
            isStaticCall: EVMCallModeHelpers.isStaticCall()
        });

        tokensOut = new address[](numTokens);
        amountsOut = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            if (wrappedAmountsOut[i] == 0) {
                tokensOut[i] = address(erc4626PoolTokens[i]);
            } else {
                (tokensOut[i], amountsOut[i]) = _processTokenOut(
                    address(erc4626PoolTokens[i]),
                    wrappedAmountsOut[i],
                    unwrapWrapped[i],
                    params.minAmountsOut[i],
                    callParams
                );
            }
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
    function _validateHookParams(
        address pool,
        uint256 amountsLength,
        uint256 wrapLength
    ) private view returns (IERC20[] memory poolTokens, uint256 numTokens) {
        poolTokens = _vault.getPoolTokens(pool);
        numTokens = poolTokens.length;

        InputHelpers.ensureInputLengthMatch(numTokens, amountsLength, wrapLength);
    }

    /**
     * @notice Wraps the underlying tokens specified in the transient set `_currentSwapTokenInAmounts`.
     * @dev Then updates this set with the resulting amount of wrapped tokens from the operation.
     * @param wrappedToken The token to wrap
     * @param sender The address of the originator of the transaction
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @return wrappedAmountOut The amountOut of wrapped tokens
     */
    function _wrapAndUpdateTokenInAmounts(
        IERC4626 wrappedToken,
        address sender,
        bool wethIsEth
    ) private returns (uint256 wrappedAmountOut) {
        address underlyingToken = _vault.getERC4626BufferAsset(wrappedToken);

        // Get the amountIn of underlying tokens specified by the sender.
        uint256 underlyingAmountIn = _currentSwapTokenInAmounts().tGet(underlyingToken);
        RouterCallParams memory callParams = RouterCallParams({
            sender: sender,
            wethIsEth: wethIsEth,
            isStaticCall: EVMCallModeHelpers.isStaticCall()
        });

        wrappedAmountOut = _executeWrapOperation(wrappedToken, underlyingToken, underlyingAmountIn, callParams);

        // Remove the underlying token from `_currentSwapTokensIn` and zero out the amount, as these tokens were paid
        // in advance and wrapped. Remaining tokens will be transferred in at the end of the calculation.
        _currentSwapTokensIn().remove(underlyingToken);
        _currentSwapTokenInAmounts().tSet(underlyingToken, 0);
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
    function _processTokenIn(
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

            actualAmountIn = _executeWrapOperation(wrappedToken, underlyingToken, amountIn, callParams);
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
     * @return tokenIn The final incoming token (the underlying token if wrapped)
     * @return actualAmountIn The final token amount (of the underlying token if wrapped)
     */
    function _processTokenInExactOut(
        address token,
        uint256 amountIn,
        bool needToWrap,
        uint256 maxAmountIn,
        RouterCallParams memory callParams
    ) private returns (address tokenIn, uint256 actualAmountIn) {
        if (needToWrap) {
            IERC4626 wrappedToken = IERC4626(token);
            IERC20 underlyingToken = IERC20(_vault.getBufferAsset(wrappedToken));

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

            tokenIn = address(underlyingToken);
        } else {
            if (callParams.isStaticCall == false) {
                _takeTokenIn(callParams.sender, IERC20(token), amountIn, callParams.wethIsEth);
            }

            actualAmountIn = amountIn;
            tokenIn = token;
        }

        if (actualAmountIn > maxAmountIn) {
            revert IVaultErrors.AmountInAboveMax(IERC20(token), amountIn, maxAmountIn);
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
     * @return tokenOut The address of the actual outgoing token (underlying if unwrapped)
     * @return actualAmountOut The actual amountOut (in underlying token if unwrapped)
     */
    function _processTokenOut(
        address token,
        uint256 amountOut,
        bool needToUnwrap,
        uint256 minAmountOut,
        RouterCallParams memory callParams
    ) private returns (address tokenOut, uint256 actualAmountOut) {
        if (needToUnwrap) {
            IERC4626 wrappedToken = IERC4626(token);
            IERC20 underlyingToken = IERC20(_vault.getERC4626BufferAsset(wrappedToken));

            if (address(underlyingToken) == address(0)) {
                revert IVaultErrors.BufferNotInitialized(wrappedToken);
            }

            (, , actualAmountOut) = _vault.erc4626BufferWrapOrUnwrap(
                BufferWrapOrUnwrapParams({
                    kind: SwapKind.EXACT_IN,
                    direction: WrappingDirection.UNWRAP,
                    wrappedToken: wrappedToken,
                    amountGivenRaw: amountOut,
                    limitRaw: minAmountOut
                })
            );
            tokenOut = address(underlyingToken);

            if (callParams.isStaticCall == false) {
                _sendTokenOut(callParams.sender, underlyingToken, actualAmountOut, callParams.wethIsEth);
            }
        } else {
            actualAmountOut = amountOut;
            tokenOut = token;

            if (callParams.isStaticCall == false) {
                _sendTokenOut(callParams.sender, IERC20(token), actualAmountOut, callParams.wethIsEth);
            }
        }

        if (actualAmountOut < minAmountOut) {
            revert IVaultErrors.AmountOutBelowMin(IERC20(tokenOut), actualAmountOut, minAmountOut);
        }
    }

    /**
     * @notice Centralized handler for ERC4626 wrapping operations.
     * @param wrappedToken The ERC4626 token to wrap into
     * @param underlyingAmount Amount of underlying tokens to wrap
     * @param callParams Common parameters from the main router call
     * @return wrappedAmount Amount of wrapped tokens received
     */
    function _executeWrapOperation(
        IERC4626 wrappedToken,
        address underlyingToken,
        uint256 underlyingAmount,
        RouterCallParams memory callParams
    ) internal returns (uint256 wrappedAmount) {
        if (underlyingAmount == 0) {
            return 0;
        }

        if (callParams.isStaticCall == false) {
            _takeTokenIn(callParams.sender, IERC20(underlyingToken), underlyingAmount, callParams.wethIsEth);
        }

        (, , wrappedAmount) = _vault.erc4626BufferWrapOrUnwrap(
            BufferWrapOrUnwrapParams({
                kind: SwapKind.EXACT_IN,
                direction: WrappingDirection.WRAP,
                wrappedToken: wrappedToken,
                amountGivenRaw: underlyingAmount,
                limitRaw: 0
            })
        );

        _vault.settle(IERC20(address(wrappedToken)), wrappedAmount);
    }

    /**
     * @notice Centralized handler for ERC4626 unwrapping operations.
     * @param wrappedToken The ERC4626 token to unwrap from
     * @param wrappedAmount Amount of wrapped tokens to unwrap
     * @return underlyingAmount Amount of underlying tokens received
     */
    function _executeUnwrapOperation(
        IERC4626 wrappedToken,
        uint256 wrappedAmount
    ) internal returns (uint256 underlyingAmount) {
        if (wrappedAmount == 0) {
            return 0;
        }

        (, , underlyingAmount) = _vault.erc4626BufferWrapOrUnwrap(
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

    /***************************************************************************
                                   Nested pools
    ***************************************************************************/

    /// @inheritdoc ICompositeLiquidityRouter
    function addLiquidityUnbalancedNestedPool(
        address parentPool,
        address[] memory tokensIn,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        CompositeLiquidityRouter.addLiquidityUnbalancedNestedPoolHook,
                        (
                            AddLiquidityHookParams({
                                pool: parentPool,
                                sender: msg.sender,
                                maxAmountsIn: exactAmountsIn,
                                minBptAmountOut: minBptAmountOut,
                                kind: AddLiquidityKind.UNBALANCED,
                                wethIsEth: wethIsEth,
                                userData: userData
                            }),
                            tokensIn
                        )
                    )
                ),
                (uint256)
            );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function queryAddLiquidityUnbalancedNestedPool(
        address parentPool,
        address[] memory tokensIn,
        uint256[] memory exactAmountsIn,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256) {
        AddLiquidityHookParams memory params = _buildQueryAddLiquidityParams(
            parentPool,
            exactAmountsIn,
            0,
            AddLiquidityKind.UNBALANCED,
            userData
        );

        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(CompositeLiquidityRouter.addLiquidityUnbalancedNestedPoolHook, (params, tokensIn))
                ),
                (uint256)
            );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function removeLiquidityProportionalNestedPool(
        address parentPool,
        uint256 exactBptAmountIn,
        address[] memory tokensOut,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256[] memory amountsOut) {
        (amountsOut) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    CompositeLiquidityRouter.removeLiquidityProportionalNestedPoolHook,
                    (
                        RemoveLiquidityHookParams({
                            sender: msg.sender,
                            pool: parentPool,
                            minAmountsOut: minAmountsOut,
                            maxBptAmountIn: exactBptAmountIn,
                            kind: RemoveLiquidityKind.PROPORTIONAL,
                            wethIsEth: wethIsEth,
                            userData: userData
                        }),
                        tokensOut
                    )
                )
            ),
            (uint256[])
        );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function queryRemoveLiquidityProportionalNestedPool(
        address parentPool,
        uint256 exactBptAmountIn,
        address[] memory tokensOut,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256[] memory amountsOut) {
        RemoveLiquidityHookParams memory params = _buildQueryRemoveLiquidityParams(
            parentPool,
            exactBptAmountIn,
            tokensOut.length,
            userData
        );

        (amountsOut) = abi.decode(
            _vault.quote(
                abi.encodeCall(CompositeLiquidityRouter.removeLiquidityProportionalNestedPoolHook, (params, tokensOut))
            ),
            (uint256[])
        );
    }

    // Nested Pool Hooks

    function removeLiquidityProportionalNestedPoolHook(
        RemoveLiquidityHookParams calldata params,
        address[] memory tokensOut
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
            address childToken = address(parentPoolTokens[i]);
            uint256 parentPoolAmountOut = parentPoolAmountsOut[i];

            CompositeTokenType childTokenType = _getCompositeTokenType(childToken);

            if (childTokenType == CompositeTokenType.BPT) {
                // Token is a BPT, so remove liquidity from the child pool.

                // We don't expect the sender to have BPT to burn. So, we flashloan tokens here (which should in
                // practice just use the existing credit).
                _vault.sendTo(IERC20(childToken), address(this), parentPoolAmountOut);

                IERC20[] memory childPoolTokens = _vault.getPoolTokens(childToken);
                // Router is an intermediary in this case. The Vault will burn tokens from the Router, so the Router
                // is both owner and spender (which doesn't need approval).
                (, uint256[] memory childPoolAmountsOut, ) = _vault.removeLiquidity(
                    RemoveLiquidityParams({
                        pool: childToken,
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
                    if (childPoolTokenType == CompositeTokenType.ERC4626) {
                        // Token is an ERC4626 wrapper, so unwrap it and return the underlying.
                        _executeUnwrapOperation(IERC4626(childPoolToken), childPoolAmountOut);
                    } else {
                        _currentSwapTokensOut().add(childPoolToken);
                        _currentSwapTokenOutAmounts().tAdd(childPoolToken, childPoolAmountOut);
                    }
                }
            } else if (childTokenType == CompositeTokenType.ERC4626) {
                // Token is an ERC4626 wrapper, so unwrap it and return the underlying.
                _executeUnwrapOperation(IERC4626(childToken), parentPoolAmountOut);
            } else {
                // Token is neither a BPT nor ERC4626, so return the amount to the user.
                _currentSwapTokensOut().add(childToken);
                _currentSwapTokenOutAmounts().tAdd(childToken, parentPoolAmountOut);
            }
        }

        if (_currentSwapTokensOut().length() != tokensOut.length) {
            // If tokensOut length does not match transient tokens out length, the tokensOut array is wrong.
            revert WrongTokensOut(_currentSwapTokensOut().values(), tokensOut);
        }

        // The hook writes current swap token and token amounts out.
        uint256 numTokensOut = tokensOut.length;
        amountsOut = new uint256[](numTokensOut);

        bool[] memory checkedTokenIndexes = new bool[](numTokensOut);
        for (uint256 i = 0; i < numTokensOut; ++i) {
            address tokenOut = tokensOut[i];
            uint256 tokenIndex = _currentSwapTokensOut().indexOf(tokenOut);

            if (_currentSwapTokensOut().contains(tokenOut) == false || checkedTokenIndexes[tokenIndex]) {
                // If tokenOut is not in transient tokens out array or token is repeated, the tokensOut array is wrong.
                revert WrongTokensOut(_currentSwapTokensOut().values(), tokensOut);
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

    function addLiquidityUnbalancedNestedPoolHook(
        AddLiquidityHookParams calldata params,
        address[] memory tokensIn
    ) external nonReentrant onlyVault returns (uint256 exactBptAmountOut) {
        // Revert if tokensIn length does not match maxAmountsIn length.
        InputHelpers.ensureInputLengthMatch(params.maxAmountsIn.length, tokensIn.length);

        // Loads a Set with all amounts to be inserted in the nested pools, so we don't need to iterate over the tokens
        // array to find the child pool amounts to insert.
        for (uint256 i = 0; i < tokensIn.length; ++i) {
            if (params.maxAmountsIn[i] == 0) {
                continue;
            }

            _currentSwapTokenInAmounts().tSet(tokensIn[i], params.maxAmountsIn[i]);
            _currentSwapTokensIn().add(tokensIn[i]);
        }

        (uint256[] memory amountsIn, ) = _addLiquidityToNestedPool(params.pool, params);
        bool isStaticCall = EVMCallModeHelpers.isStaticCall();

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

        // Settle the amounts in.
        if (isStaticCall == false) {
            _settlePaths(params.sender, params.wethIsEth);
        }
    }

    // Nested Pool helper functions

    function _addLiquidityToNestedPool(
        address pool,
        AddLiquidityHookParams calldata params
    ) internal returns (uint256[] memory amountsIn, bool allAmountsEmpty) {
        IERC20[] memory parentPoolTokens = _vault.getPoolTokens(pool);
        amountsIn = new uint256[](parentPoolTokens.length);
        allAmountsEmpty = true;

        for (uint256 i = 0; i < parentPoolTokens.length; i++) {
            address token = address(parentPoolTokens[i]);
            CompositeTokenInfo memory tokenInfo = _computeCompositeTokenInfo(
                token,
                _currentSwapTokenInAmounts().tGet(token)
            );

            amountsIn[i] = _settledTokenAmounts().tGet(token) > 0
                ? _settledTokenAmounts().tGet(token)
                : _processNestedPoolToken(tokenInfo, params);

            if (amountsIn[i] > 0) {
                allAmountsEmpty = false;
            }
        }
    }

    function _processNestedPoolToken(
        CompositeTokenInfo memory tokenInfo,
        AddLiquidityHookParams calldata params
    ) internal returns (uint256 amountOut) {
        address token = tokenInfo.token;

        if (tokenInfo.tokenType == CompositeTokenType.BPT) {
            amountOut = _addLiquidityToChildPool(token, params);
        } else if (tokenInfo.tokenType == CompositeTokenType.ERC4626 && tokenInfo.needToWrap) {
            amountOut = _wrapAndUpdateTokenInAmounts(IERC4626(token), params.sender, params.wethIsEth);
        } else {
            amountOut = _currentSwapTokenInAmounts().tGet(token);
        }

        _settledTokenAmounts().tSet(token, amountOut);
    }

    function _addLiquidityToChildPool(
        address childPool,
        AddLiquidityHookParams calldata params
    ) internal returns (uint256 childBptAmountOut) {
        IERC20[] memory childPoolTokens = _vault.getPoolTokens(childPool);
        uint256[] memory childPoolAmountsIn = new uint256[](childPoolTokens.length);
        bool childPoolAmountsEmpty = true;

        // Process tokens in the child pool (no further nesting allowed).
        for (uint256 j = 0; j < childPoolTokens.length; j++) {
            address childPoolToken = address(childPoolTokens[j]);

            CompositeTokenInfo memory tokenInfo = _computeCompositeTokenInfo(
                childPoolToken,
                _currentSwapTokenInAmounts().tGet(childPoolToken)
            );

            if (tokenInfo.tokenType == CompositeTokenType.BPT) {
                // This would be a second level of nesting, which is not supported. Process as a standard ERC20 token.
                if (_settledTokenAmounts().tGet(childPoolToken) == 0) {
                    childPoolAmountsIn[j] = tokenInfo.amount;
                    _settledTokenAmounts().tSet(childPoolToken, tokenInfo.amount);
                }
            } else if (
                // wrapped amount in was not specified.
                tokenInfo.tokenType == CompositeTokenType.ERC4626 && tokenInfo.amount == 0
            ) {
                // Handle ERC4626 token wrapping at child pool level.
                childPoolAmountsIn[j] = _wrapAndUpdateTokenInAmounts(
                    IERC4626(childPoolToken),
                    params.sender,
                    params.wethIsEth
                );
            } else if (_settledTokenAmounts().tGet(childPoolToken) == 0) {
                // Set this token's amountIn if it's a standard token that was not previously settled.
                childPoolAmountsIn[j] = tokenInfo.amount;
                _settledTokenAmounts().tSet(childPoolToken, tokenInfo.amount);
            }

            if (childPoolAmountsIn[j] > 0) {
                childPoolAmountsEmpty = false;
            }
        }

        if (childPoolAmountsEmpty == false) {
            // Add Liquidity will mint childTokens to the Vault, so the insertion of liquidity in the parent
            // pool will be an accounting adjustment, not a token transfer.
            (, uint256 exactChildBptAmountOut, ) = _vault.addLiquidity(
                AddLiquidityParams({
                    pool: childPool,
                    to: address(_vault),
                    maxAmountsIn: childPoolAmountsIn,
                    minBptAmountOut: 0,
                    kind: params.kind,
                    userData: params.userData
                })
            );

            childBptAmountOut = exactChildBptAmountOut;

            // Since the BPT will be add to the parent pool, get the credit from the inserted BPT in advance.
            _vault.settle(IERC20(childPool), exactChildBptAmountOut);
        }
    }

    // Fill in the information needed to correctly process nested pool tokens.
    function _computeCompositeTokenInfo(
        address token,
        uint256 amount
    ) private view returns (CompositeTokenInfo memory info) {
        info.token = token;
        info.amount = amount;
        info.tokenType = _getCompositeTokenType(token);

        if (info.tokenType == CompositeTokenType.ERC4626) {
            info.needToWrap = (amount == 0 &&
                _currentSwapTokenInAmounts().tGet(_vault.getERC4626BufferAsset(IERC4626(token))) > 0);
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

    // Common helper functions

    // Construct a set of add liquidity hook params, adding in the invariant parameters.
    function _buildQueryAddLiquidityParams(
        address pool,
        uint256[] memory maxAmountsOrExactOut,
        uint256 minBptOrExactBpt,
        AddLiquidityKind kind,
        bytes memory userData
    ) private view returns (AddLiquidityHookParams memory) {
        return
            AddLiquidityHookParams({
                sender: address(this), // Always use router address for queries
                pool: pool,
                maxAmountsIn: kind == AddLiquidityKind.PROPORTIONAL ? _maxTokenLimits(pool) : maxAmountsOrExactOut,
                minBptAmountOut: kind == AddLiquidityKind.PROPORTIONAL ? minBptOrExactBpt : 0,
                kind: kind,
                wethIsEth: false, // Always false for queries
                userData: userData
            });
    }

    // Construct a set of remove liquidity hook params, adding in the invariant parameters.
    function _buildQueryRemoveLiquidityParams(
        address pool,
        uint256 exactBptAmountIn,
        uint256 numTokens,
        bytes memory userData
    ) private view returns (RemoveLiquidityHookParams memory) {
        return
            RemoveLiquidityHookParams({
                sender: address(this), // Always use router address for queries
                pool: pool,
                minAmountsOut: new uint256[](numTokens), // Always zero for supported use cases
                maxBptAmountIn: exactBptAmountIn,
                kind: RemoveLiquidityKind.PROPORTIONAL, // Always proportional for supported use cases
                wethIsEth: false, // Always false for queries
                userData: userData
            });
    }
}
