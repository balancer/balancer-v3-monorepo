// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { ICompositeLiquidityRouter } from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import {
    TransientEnumerableSet
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/TransientEnumerableSet.sol";
import {
    TransientStorageHelpers,
    Bytes32ToUintMappingSlot
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

import { BatchRouterCommon } from "./BatchRouterCommon.sol";

/**
 * @notice Entrypoint for add/remove liquidity operations on ERC4626 and nested pools.
 * @dev The external API functions unlock the Vault, which calls back into the corresponding hook functions.
 * These execute the steps needed to add to and remove liquidity from these special types of pools, and settle
 * the operation with the Vault.
 */
contract CompositeLiquidityRouter is ICompositeLiquidityRouter, BatchRouterCommon, ReentrancyGuardTransient {
    using TransientEnumerableSet for TransientEnumerableSet.AddressSet;
    using TransientStorageHelpers for *;

    bytes32 private immutable _INDEX_BY_POOL_MAPPING_SLOT = _calculateBatchRouterStorageSlot("indexByPoolMapping");

    constructor(IVault vault, IWETH weth, IPermit2 permit2) BatchRouterCommon(vault, weth, permit2) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /*******************************************************************************
                                ERC4626 Pools
    *******************************************************************************/

    /// @inheritdoc ICompositeLiquidityRouter
    function addLiquidityProportionalToERC4626Pool(
        address pool,
        uint256[] memory maxUnderlyingAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256[] memory underlyingAmountsIn) {
        underlyingAmountsIn = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    CompositeLiquidityRouter.addLiquidityERC4626PoolProportionalHook,
                    AddLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        maxAmountsIn: maxUnderlyingAmountsIn,
                        minBptAmountOut: exactBptAmountOut,
                        kind: AddLiquidityKind.PROPORTIONAL,
                        wethIsEth: wethIsEth,
                        userData: userData
                    })
                )
            ),
            (uint256[])
        );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function removeLiquidityProportionalFromERC4626Pool(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minUnderlyingAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256[] memory underlyingAmountsOut) {
        underlyingAmountsOut = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    CompositeLiquidityRouter.removeLiquidityERC4626PoolProportionalHook,
                    RemoveLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        minAmountsOut: minUnderlyingAmountsOut,
                        maxBptAmountIn: exactBptAmountIn,
                        kind: RemoveLiquidityKind.PROPORTIONAL,
                        wethIsEth: wethIsEth,
                        userData: userData
                    })
                )
            ),
            (uint256[])
        );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function queryAddLiquidityProportionalToERC4626Pool(
        address pool,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256[] memory underlyingAmountsIn) {
        underlyingAmountsIn = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    CompositeLiquidityRouter.addLiquidityERC4626PoolProportionalHook,
                    AddLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        maxAmountsIn: _maxTokenLimits(pool),
                        minBptAmountOut: exactBptAmountOut,
                        kind: AddLiquidityKind.PROPORTIONAL,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256[])
        );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function queryRemoveLiquidityProportionalFromERC4626Pool(
        address pool,
        uint256 exactBptAmountIn,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (uint256[] memory underlyingAmountsOut) {
        underlyingAmountsOut = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    CompositeLiquidityRouter.removeLiquidityERC4626PoolProportionalHook,
                    RemoveLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        minAmountsOut: new uint256[](2),
                        maxBptAmountIn: exactBptAmountIn,
                        kind: RemoveLiquidityKind.PROPORTIONAL,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256[])
        );
    }

    function addLiquidityERC4626PoolProportionalHook(
        AddLiquidityHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256[] memory underlyingAmountsIn) {
        IERC20[] memory erc4626PoolTokens = _vault.getPoolTokens(params.pool);
        uint256 poolTokensLength = erc4626PoolTokens.length;

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

        underlyingAmountsIn = new uint256[](poolTokensLength);
        for (uint256 i = 0; i < poolTokensLength; i++) {
            (underlyingAmountsIn[i], ) = _wrapToken(
                params.sender,
                erc4626PoolTokens[i],
                wrappedAmountsIn[i],
                SwapKind.EXACT_OUT,
                params.maxAmountsIn[i],
                EVMCallModeHelpers.isStaticCall(),
                params.wethIsEth
            );
        }
    }

    function removeLiquidityERC4626PoolProportionalHook(
        RemoveLiquidityHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256[] memory underlyingAmountsOut) {
        IERC20[] memory erc4626PoolTokens = _vault.getPoolTokens(params.pool);
        uint256 poolTokensLength = erc4626PoolTokens.length;
        underlyingAmountsOut = new uint256[](poolTokensLength);

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

        bool isStaticCall = EVMCallModeHelpers.isStaticCall();

        for (uint256 i = 0; i < poolTokensLength; ++i) {
            IERC4626 wrappedToken = IERC4626(address(erc4626PoolTokens[i]));
            IERC20 underlyingToken = IERC20(_vault.getBufferAsset(wrappedToken));

            // If the Vault returns address 0 as underlying, it means that the ERC4626 token buffer was not
            // initialized. Thus, the Router treats it as a non-ERC4626 token.
            if (address(underlyingToken) == address(0)) {
                underlyingAmountsOut[i] = wrappedAmountsOut[i];
                if (isStaticCall == false) {
                    _sendTokenOut(params.sender, erc4626PoolTokens[i], underlyingAmountsOut[i], params.wethIsEth);
                }
                continue;
            }

            // `erc4626BufferWrapOrUnwrap` will fail if the wrappedToken is not ERC4626-conforming.
            (, , underlyingAmountsOut[i]) = _vault.erc4626BufferWrapOrUnwrap(
                BufferWrapOrUnwrapParams({
                    kind: SwapKind.EXACT_IN,
                    direction: WrappingDirection.UNWRAP,
                    wrappedToken: wrappedToken,
                    amountGivenRaw: wrappedAmountsOut[i],
                    limitRaw: params.minAmountsOut[i]
                })
            );

            if (isStaticCall == false) {
                _sendTokenOut(params.sender, underlyingToken, underlyingAmountsOut[i], params.wethIsEth);
            }
        }
    }

    /***************************************************************************
                                   Nested pools
    ***************************************************************************/

    /// @inheritdoc ICompositeLiquidityRouter
    function addLiquidityUnbalancedNestedPool(
        address mainPool,
        NestedPoolOperation[] calldata nestedPoolOperations
    ) external saveSender(msg.sender) returns (uint256) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeWithSelector(
                        CompositeLiquidityRouter.addLiquidityUnbalancedNestedPoolHook.selector,
                        AddLiquidityNestedPoolHookParams({
                            pool: mainPool,
                            sender: msg.sender,
                            kind: AddLiquidityKind.UNBALANCED,
                            nestedPoolOperations: nestedPoolOperations
                        })
                    )
                ),
                (uint256)
            );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function queryAddLiquidityUnbalancedNestedPool(
        address mainPool,
        NestedPoolOperation[] calldata nestedPoolOperations,
        address sender
    ) external saveSender(sender) returns (uint256) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeWithSelector(
                        CompositeLiquidityRouter.addLiquidityUnbalancedNestedPoolHook.selector,
                        AddLiquidityNestedPoolHookParams({
                            pool: mainPool,
                            sender: sender,
                            kind: AddLiquidityKind.UNBALANCED,
                            nestedPoolOperations: nestedPoolOperations
                        })
                    )
                ),
                (uint256)
            );
    }

    function addLiquidityUnbalancedNestedPoolHook(
        AddLiquidityNestedPoolHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256 exactBptAmountOut) {
        _fillNestedPoolOperationIndexByPoolMapping(params.nestedPoolOperations);

        return _addLiquidityNestedPool(params.pool, address(0), params.pool, params, EVMCallModeHelpers.isStaticCall());
    }

    function _addLiquidityNestedPool(
        address mainPool,
        address prevPool,
        address pool,
        AddLiquidityNestedPoolHookParams calldata params,
        bool isStaticCall
    ) internal returns (uint256 bptAmountOut) {
        IERC20[] memory childTokens = _vault.getPoolTokens(pool);
        uint256[] memory childTokensAmountsIn = new uint256[](childTokens.length);

        (
            bool isPoolNestedPoolOperationExist,
            NestedPoolOperation memory nestedPoolOperation
        ) = _getNestedPoolOperationByPool(prevPool, pool, params.nestedPoolOperations);

        bool doNeedToAddLiquidityToPool = isPoolNestedPoolOperationExist;

        for (uint256 i = 0; i < childTokens.length; i++) {
            address childToken = address(childTokens[i]);

            if (_vault.isPoolRegistered(childToken)) {
                childTokensAmountsIn[i] = _addLiquidityNestedPool(mainPool, pool, childToken, params, isStaticCall);
            } else if (_vault.isERC4626BufferInitialized(IERC4626(childToken))) {
                (
                    bool isERC4626PoolOperationExist,
                    NestedPoolOperation memory erc4626NestedPoolOperation
                ) = _getNestedPoolOperationByPool(pool, childToken, params.nestedPoolOperations);

                if (isERC4626PoolOperationExist) {
                    bool isStaticCall_ = isStaticCall; // Avoid stack too deep error
                    (, uint256 wrappedAmount) = _wrapToken(
                        params.sender,
                        IERC20(childToken),
                        erc4626NestedPoolOperation.tokensInAmounts[0], // Only one token can be wrapped in ERC4626 pools
                        SwapKind.EXACT_IN,
                        0,
                        isStaticCall_,
                        erc4626NestedPoolOperation.wethIsEth
                    );
                    childTokensAmountsIn[i] = wrappedAmount;
                } else if (isPoolNestedPoolOperationExist && nestedPoolOperation.tokensInAmounts[i] > 0) {
                    childTokensAmountsIn[i] = nestedPoolOperation.tokensInAmounts[i];

                    if (isStaticCall == false) {
                        _takeTokenIn(params.sender, IERC20(childToken), childTokensAmountsIn[i], false);
                    }
                }
            } else if (isPoolNestedPoolOperationExist && nestedPoolOperation.tokensInAmounts[i] > 0) {
                childTokensAmountsIn[i] = nestedPoolOperation.tokensInAmounts[i];

                if (isStaticCall == false) {
                    _takeTokenIn(params.sender, IERC20(childToken), childTokensAmountsIn[i], false);
                }
            }

            if (doNeedToAddLiquidityToPool == false && childTokensAmountsIn[i] > 0) {
                doNeedToAddLiquidityToPool = true;
            }
        }

        if (doNeedToAddLiquidityToPool == false) {
            return 0;
        }

        (, bptAmountOut, ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: params.sender,
                maxAmountsIn: childTokensAmountsIn,
                minBptAmountOut: isPoolNestedPoolOperationExist ? nestedPoolOperation.minBptAmountOut : 0,
                kind: params.kind,
                userData: isPoolNestedPoolOperationExist ? nestedPoolOperation.userData : new bytes(0)
            })
        );

        if (pool != mainPool && isStaticCall == false) {
            // // Since the BPT will be inserted into the parent pool, gets the credit from the inserted BPTs in
            // // advance
            _takeTokenIn(params.sender, IERC20(pool), bptAmountOut, false);
        }
    }

    /**
     * @notice Wraps the underlying tokens specified in the transient set `_currentSwapTokenInAmounts`, and updates
     * this set with the resulting amount of wrapped tokens from the operation.
     */
    function _wrapAndUpdateTokenInAmounts(IERC4626 wrappedToken) private returns (uint256 wrappedAmountOut) {
        address underlyingToken = wrappedToken.asset();

        // Get the amountIn of underlying tokens informed by the sender.
        uint256 underlyingAmountIn = _currentSwapTokenInAmounts().tGet(underlyingToken);
        if (underlyingAmountIn == 0) {
            return 0;
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

        // Remove the underlying amount from `_currentSwapTokenInAmounts` and add the wrapped amount.
        _currentSwapTokenInAmounts().tSet(underlyingToken, 0);
        _currentSwapTokenInAmounts().tSet(address(wrappedToken), wrappedAmountOut);

        // Updates the reserves of the vault with the wrappedToken amount.
        _vault.settle(IERC20(address(wrappedToken)), wrappedAmountOut);
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function removeLiquidityProportionalNestedPool(
        address parentPool,
        uint256 exactBptAmountIn,
        address[] memory tokensOut,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) external saveSender(msg.sender) returns (uint256[] memory amountsOut) {
        (amountsOut) = abi.decode(
            _vault.unlock(
                abi.encodeWithSelector(
                    CompositeLiquidityRouter.removeLiquidityProportionalNestedPoolHook.selector,
                    RemoveLiquidityHookParams({
                        sender: msg.sender,
                        pool: parentPool,
                        minAmountsOut: minAmountsOut,
                        maxBptAmountIn: exactBptAmountIn,
                        kind: RemoveLiquidityKind.PROPORTIONAL,
                        wethIsEth: false,
                        userData: userData
                    }),
                    tokensOut
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
        (amountsOut) = abi.decode(
            _vault.quote(
                abi.encodeWithSelector(
                    CompositeLiquidityRouter.removeLiquidityProportionalNestedPoolHook.selector,
                    RemoveLiquidityHookParams({
                        sender: msg.sender,
                        pool: parentPool,
                        minAmountsOut: new uint256[](tokensOut.length),
                        maxBptAmountIn: exactBptAmountIn,
                        kind: RemoveLiquidityKind.PROPORTIONAL,
                        wethIsEth: false,
                        userData: userData
                    }),
                    tokensOut
                )
            ),
            (uint256[])
        );
    }

    function removeLiquidityProportionalNestedPoolHook(
        RemoveLiquidityHookParams calldata params,
        address[] memory tokensOut
    ) external nonReentrant onlyVault returns (uint256[] memory amountsOut) {
        IERC20[] memory parentPoolTokens = _vault.getPoolTokens(params.pool);

        bool isStaticCall = EVMCallModeHelpers.isStaticCall();

        // Revert if tokensOut length does not match with minAmountsOut length.
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

            if (_vault.isPoolRegistered(childToken)) {
                // Token is a BPT, so remove liquidity from the child pool.

                // We don't expect the sender to have BPT to burn. So, we flashloan tokens here (which should in
                // practice just use existing credit).
                _vault.sendTo(IERC20(childToken), address(this), parentPoolAmountsOut[i]);

                IERC20[] memory childPoolTokens = _vault.getPoolTokens(childToken);
                // Router is an intermediary in this case. The Vault will burn tokens from the Router, so Router is
                // both owner and spender (which doesn't need approval).
                (, uint256[] memory childPoolAmountsOut, ) = _vault.removeLiquidity(
                    RemoveLiquidityParams({
                        pool: childToken,
                        from: address(this),
                        maxBptAmountIn: parentPoolAmountsOut[i],
                        minAmountsOut: new uint256[](childPoolTokens.length),
                        kind: params.kind,
                        userData: params.userData
                    })
                );
                // Return amounts to user.
                for (uint256 j = 0; j < childPoolTokens.length; j++) {
                    address childPoolToken = address(childPoolTokens[j]);
                    if (_vault.isERC4626BufferInitialized(IERC4626(childPoolToken))) {
                        // Token is an ERC4626 wrapper, so unwrap it and return the underlying.
                        _unwrapAndUpdateTokenOutAmounts(IERC4626(childPoolToken), childPoolAmountsOut[j]);
                    } else {
                        _currentSwapTokensOut().add(childPoolToken);
                        _currentSwapTokenOutAmounts().tAdd(childPoolToken, childPoolAmountsOut[j]);
                    }
                }
            } else if (_vault.isERC4626BufferInitialized(IERC4626(childToken))) {
                // Token is an ERC4626 wrapper, so unwrap it and return the underlying.
                _unwrapAndUpdateTokenOutAmounts(IERC4626(childToken), parentPoolAmountsOut[i]);
            } else {
                // Token is neither a BPT nor ERC4626, so return the amount to the user.
                _currentSwapTokensOut().add(childToken);
                _currentSwapTokenOutAmounts().tAdd(childToken, parentPoolAmountsOut[i]);
            }
        }

        if (_currentSwapTokensOut().length() != tokensOut.length) {
            // If tokensOut length does not match with transient tokens out length, the tokensOut array is wrong.
            revert WrongTokensOut(_currentSwapTokensOut().values(), tokensOut);
        }

        // The hook writes current swap token and token amounts out.
        amountsOut = new uint256[](tokensOut.length);
        // If a certain token index was already iterated on, reverts.
        bool[] memory checkedTokenIndexes = new bool[](tokensOut.length);
        for (uint256 i = 0; i < tokensOut.length; ++i) {
            uint256 tokenIndex = _currentSwapTokensOut().indexOf(tokensOut[i]);
            if (_currentSwapTokensOut().contains(tokensOut[i]) == false || checkedTokenIndexes[tokenIndex]) {
                // If tokenOut is not in transient tokens out array or token is repeated, the tokensOut array is wrong.
                revert WrongTokensOut(_currentSwapTokensOut().values(), tokensOut);
            }

            // Informs that the token in the transient array index has already been checked.
            checkedTokenIndexes[tokenIndex] = true;

            amountsOut[i] = _currentSwapTokenOutAmounts().tGet(tokensOut[i]);

            if (amountsOut[i] < params.minAmountsOut[i]) {
                revert IVaultErrors.AmountOutBelowMin(IERC20(tokensOut[i]), amountsOut[i], params.minAmountsOut[i]);
            }
        }

        if (isStaticCall == false) {
            _settlePaths(params.sender, false);
        }
    }

    /***************************************************************************
                            Internal & Private functions
    ***************************************************************************/

    function _wrapToken(
        address sender,
        IERC20 erc4626PoolToken,
        uint256 amountsIn,
        SwapKind kind,
        uint256 limit,
        bool isStaticCall,
        bool wethIsEth
    ) private returns (uint256 underlyingAmount, uint256 wrappedAmount) {
        // Treat all ERC4626 pool tokens as wrapped. The next step will verify if we can use the wrappedToken as
        // a valid ERC4626.
        IERC4626 wrappedToken = IERC4626(address(erc4626PoolToken));
        IERC20 underlyingToken = IERC20(_vault.getBufferAsset(wrappedToken));

        // If the Vault returns address 0 as underlying, it means that the ERC4626 token buffer was not
        // initialized. Thus, the Router treats it as a non-ERC4626 token.
        if (address(underlyingToken) == address(0)) {
            if (isStaticCall == false) {
                _takeTokenIn(sender, erc4626PoolToken, amountsIn, wethIsEth);
            }

            return (amountsIn, amountsIn);
        }

        if (isStaticCall == false) {
            if (kind == SwapKind.EXACT_IN) {
                // If the SwapKind is EXACT_IN, take the exact amount in from the sender.
                _takeTokenIn(sender, underlyingToken, amountsIn, wethIsEth);
            } else {
                // If the SwapKind is EXACT_OUT, the exact amount in is not known, because amountsIn is the
                // amount of wrapped tokens. Therefore, take the limit. After the wrap operation, the difference
                // between the limit and the actual underlying amount is returned to the sender.
                _takeTokenIn(sender, underlyingToken, limit, wethIsEth);
            }
        }

        // `erc4626BufferWrapOrUnwrap` will fail if the wrappedToken isn't ERC4626-conforming.
        (, underlyingAmount, wrappedAmount) = _vault.erc4626BufferWrapOrUnwrap(
            BufferWrapOrUnwrapParams({
                kind: kind,
                direction: WrappingDirection.WRAP,
                wrappedToken: wrappedToken,
                amountGivenRaw: amountsIn,
                limitRaw: limit
            })
        );

        if (isStaticCall == false && kind == SwapKind.EXACT_OUT) {
            // If the SwapKind is EXACT_OUT, the limit of underlying tokens was taken from the user, so the
            // difference between limit and exact underlying amount needs to be returned to the sender.
            _vault.sendTo(underlyingToken, sender, limit - underlyingAmount);
        }
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
        address underlyingToken = wrappedToken.asset();
        _currentSwapTokensOut().add(underlyingToken);
        _currentSwapTokenOutAmounts().tAdd(underlyingToken, underlyingAmountOut);
    }

    function _getNestedPoolOperationByPool(
        address prevPool,
        address pool,
        NestedPoolOperation[] calldata nestedPoolOperations
    ) private view returns (bool isExist, NestedPoolOperation memory parentNestedPoolOperation) {
        uint256 index = _nestedPoolOperationIndexByPoolMapping().tGet(keccak256(abi.encodePacked(prevPool, pool)));

        if (index != 0) {
            parentNestedPoolOperation = nestedPoolOperations[index - 1];
            isExist = true;
        }
    }

    function _fillNestedPoolOperationIndexByPoolMapping(NestedPoolOperation[] calldata nestedPoolOperations) private {
        for (uint256 i = 0; i < nestedPoolOperations.length; i++) {
            bytes32 key = keccak256(abi.encodePacked(nestedPoolOperations[i].prevPool, nestedPoolOperations[i].pool));
            if (_nestedPoolOperationIndexByPoolMapping().tGet(key) != 0) {
                revert("Some nestedPoolOperations have the same pool");
            }

            _nestedPoolOperationIndexByPoolMapping().tSet(key, i + 1); // 0 is reserved for not found
        }
    }

    function _nestedPoolOperationIndexByPoolMapping() private view returns (Bytes32ToUintMappingSlot slot) {
        return Bytes32ToUintMappingSlot.wrap(_INDEX_BY_POOL_MAPPING_SLOT);
    }
}
