// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { ICompositeLiquidityRouter } from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouter.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
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

/**
 * @notice Entrypoint for add/remove liquidity operations on ERC4626 pools.
 * @dev The external API functions unlock the Vault, which calls back into the corresponding hook functions.
 * These execute the steps needed to add to and remove liquidity from these special types of pools, and settle
 * the operation with the Vault.
 */
contract CompositeLiquidityRouter is ICompositeLiquidityRouter, BatchRouterCommon {
    using TransientEnumerableSet for TransientEnumerableSet.AddressSet;
    using TransientStorageHelpers for *;

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
    ) external payable saveSender(msg.sender) returns (uint256[] memory) {
        return
            abi.decode(
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
                (uint256[])
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
    ) external payable saveSender(msg.sender) returns (uint256[] memory) {
        return
            abi.decode(
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
                (uint256[])
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
    ) external saveSender(sender) returns (uint256[] memory) {
        AddLiquidityHookParams memory params = _buildQueryAddLiquidityParams(
            pool,
            new uint256[](0),
            exactBptAmountOut,
            AddLiquidityKind.PROPORTIONAL,
            userData
        );

        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        CompositeLiquidityRouter.addLiquidityERC4626PoolProportionalHook,
                        (params, wrapUnderlying)
                    )
                ),
                (uint256[])
            );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function queryRemoveLiquidityProportionalFromERC4626Pool(
        address pool,
        bool[] memory unwrapWrapped,
        uint256 exactBptAmountIn,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256[] memory) {
        IERC20[] memory erc4626PoolTokens = _vault.getPoolTokens(pool);
        RemoveLiquidityHookParams memory params = _buildQueryRemoveLiquidityProportionalParams(
            pool,
            exactBptAmountIn,
            erc4626PoolTokens.length,
            userData
        );

        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        CompositeLiquidityRouter.removeLiquidityERC4626PoolProportionalHook,
                        (params, unwrapWrapped)
                    )
                ),
                (uint256[])
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
        (IERC20[] memory erc4626PoolTokens, uint256 numTokens) = _validateHookParams(
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

        RouterCallParams memory callParams = RouterCallParams({
            sender: params.sender,
            wethIsEth: params.wethIsEth,
            isStaticCall: EVMCallModeHelpers.isStaticCall()
        });

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
        (IERC20[] memory erc4626PoolTokens, uint256 numTokens) = _validateHookParams(
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

        RouterCallParams memory callParams = RouterCallParams({
            sender: params.sender,
            wethIsEth: params.wethIsEth,
            isStaticCall: EVMCallModeHelpers.isStaticCall()
        });

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

    // Construct a set of add liquidity hook params, adding in the invariant parameters.
    function _buildQueryAddLiquidityParams(
        address pool,
        uint256[] memory maxOrExactAmountsOut,
        uint256 minOrExactBpt,
        AddLiquidityKind kind,
        bytes memory userData
    ) private view returns (AddLiquidityHookParams memory) {
        // `kind` will be either PROPORTIONAL or UNBALANCED, depending on the query.
        uint256[] memory resolvedMaxAmounts;
        uint256 resolvedBptAmount;
        if (kind == AddLiquidityKind.PROPORTIONAL) {
            resolvedMaxAmounts = _maxTokenLimits(pool);
            resolvedBptAmount = minOrExactBpt;
        } else if (kind == AddLiquidityKind.UNBALANCED) {
            resolvedMaxAmounts = maxOrExactAmountsOut;
            // resolvedBptAmount will be 0
        } else {
            // Should not happen.
            revert IVaultErrors.InvalidAddLiquidityKind();
        }

        return
            AddLiquidityHookParams({
                sender: address(this), // Always use router address for queries
                pool: pool,
                maxAmountsIn: resolvedMaxAmounts,
                minBptAmountOut: resolvedBptAmount,
                kind: kind,
                wethIsEth: false, // Always false for queries
                userData: userData
            });
    }

    // Construct a set of remove liquidity hook params, adding in the invariant parameters.
    function _buildQueryRemoveLiquidityProportionalParams(
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
