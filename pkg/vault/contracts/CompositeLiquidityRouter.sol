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
            new uint256[](erc4626PoolTokens.length),
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
        IERC20[] memory erc4626PoolTokens = _vault.getPoolTokens(params.pool);
        uint256 poolTokensLength = erc4626PoolTokens.length;

        // Revert if `poolTokens` length does not match `maxAmountsIn` and `wrapUnderlying`.
        InputHelpers.ensureInputLengthMatch(poolTokensLength, params.maxAmountsIn.length, wrapUnderlying.length);

        RouterCallParams memory callParams = RouterCallParams({
            sender: params.sender,
            wethIsEth: params.wethIsEth,
            isStaticCall: EVMCallModeHelpers.isStaticCall()
        });

        uint256[] memory amountsIn = new uint256[](poolTokensLength);
        for (uint256 i = 0; i < poolTokensLength; ++i) {
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
        IERC20[] memory erc4626PoolTokens = _vault.getPoolTokens(params.pool);
        uint256 poolTokensLength = erc4626PoolTokens.length;

        // Revert if `poolTokens` length does not match `maxAmountsIn` and `wrapUnderlying`.
        InputHelpers.ensureInputLengthMatch(poolTokensLength, params.maxAmountsIn.length, wrapUnderlying.length);

        uint256[] memory maxAmounts = new uint256[](poolTokensLength);
        for (uint256 i = 0; i < poolTokensLength; ++i) {
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

        tokensIn = new address[](poolTokensLength);
        amountsIn = new uint256[](poolTokensLength);

        for (uint256 i = 0; i < poolTokensLength; ++i) {
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
        IERC20[] memory erc4626PoolTokens = _vault.getPoolTokens(params.pool);
        uint256 poolTokensLength = erc4626PoolTokens.length;

        // Revert if `poolTokens` length does not match `minAmountsOut` and `unwrapWrapped`.
        InputHelpers.ensureInputLengthMatch(poolTokensLength, params.minAmountsOut.length, unwrapWrapped.length);

        (, uint256[] memory wrappedAmountsOut, ) = _vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: params.pool,
                from: params.sender,
                maxBptAmountIn: params.maxBptAmountIn,
                minAmountsOut: new uint256[](poolTokensLength),
                kind: params.kind,
                userData: params.userData
            })
        );

        RouterCallParams memory callParams = RouterCallParams({
            sender: params.sender,
            wethIsEth: params.wethIsEth,
            isStaticCall: EVMCallModeHelpers.isStaticCall()
        });

        tokensOut = new address[](poolTokensLength);
        amountsOut = new uint256[](poolTokensLength);

        for (uint256 i = 0; i < poolTokensLength; ++i) {
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
            IERC20 underlyingToken = IERC20(_vault.getBufferAsset(wrappedToken));

            if (address(underlyingToken) == address(0)) {
                revert IVaultErrors.BufferNotInitialized(wrappedToken);
            }

            if (callParams.isStaticCall == false) {
                _takeTokenIn(callParams.sender, underlyingToken, amountIn, callParams.wethIsEth);
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
            IERC20 underlyingToken = IERC20(_vault.getBufferAsset(wrappedToken));

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
        bool isStaticCall = EVMCallModeHelpers.isStaticCall();

        address underlyingToken = _vault.getERC4626BufferAsset(wrappedToken);

        // Get the amountIn of underlying tokens informed by the sender.
        uint256 underlyingAmountIn = _currentSwapTokenInAmounts().tGet(underlyingToken);
        if (underlyingAmountIn == 0) {
            return 0;
        }

        if (isStaticCall == false) {
            // Take the underlying token amount, required to wrap, in advance.
            _takeTokenIn(sender, IERC20(underlyingToken), underlyingAmountIn, wethIsEth);
        }

        (, , wrappedAmountOut) = _vault.erc4626BufferWrapOrUnwrap(
            BufferWrapOrUnwrapParams({
                kind: SwapKind.EXACT_IN,
                direction: WrappingDirection.WRAP,
                wrappedToken: wrappedToken,
                amountGivenRaw: underlyingAmountIn,
                limitRaw: uint256(0)
            })
        );

        // Remove the underlying token from `_currentSwapTokensIn` and zero out the amount, as these tokens were paid
        // in advance and wrapped. Remaining tokens will be transferred in at the end of the calculation.
        _currentSwapTokensIn().remove(underlyingToken);
        _currentSwapTokenInAmounts().tSet(underlyingToken, 0);

        // Updates the reserves of the vault with the wrappedToken amount.
        _vault.settle(IERC20(address(wrappedToken)), wrappedAmountOut);
    }

    /**
     * @notice Unwraps `wrappedAmountIn` tokens and updates the transient set `_currentSwapTokenOutAmounts`.
     */
    function _unwrapAndUpdateTokenOutAmounts(IERC4626 wrappedToken, uint256 wrappedAmountIn) private {
        if (wrappedAmountIn == 0) {
            return;
        }

        (, , uint256 underlyingAmountOut) = _vault.erc4626BufferWrapOrUnwrap(
            BufferWrapOrUnwrapParams({
                kind: SwapKind.EXACT_IN,
                direction: WrappingDirection.UNWRAP,
                wrappedToken: wrappedToken,
                amountGivenRaw: wrappedAmountIn,
                limitRaw: uint256(0)
            })
        );

        // The transient sets `_currentSwapTokensOut` and `_currentSwapTokenOutAmounts` must be updated, so
        // `_settlePaths` function will be able to send the token out amounts to the sender.
        address underlyingToken = _vault.getERC4626BufferAsset(wrappedToken);
        _currentSwapTokensOut().add(underlyingToken);
        _currentSwapTokenOutAmounts().tAdd(underlyingToken, underlyingAmountOut);
    }

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
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) private view returns (RemoveLiquidityHookParams memory) {
        return
            RemoveLiquidityHookParams({
                sender: address(this), // Always use router address for queries
                pool: pool,
                minAmountsOut: minAmountsOut,
                maxBptAmountIn: exactBptAmountIn,
                kind: RemoveLiquidityKind.PROPORTIONAL, // Always proportional for supported use cases
                wethIsEth: false, // Always false for queries
                userData: userData
            });
    }
}
