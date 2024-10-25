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

    struct RemoveLiquidityVars {
        address mainPool;
        address sender;
        bool isStaticCall;
        uint256 nextIndex;
        NestedPoolRemoveOperation[] nestedPoolOperations;
        RemoveAmountOut[] totalAmountsOut;
    }

    // solhint-disable var-name-mixedcase
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
                        sender: address(this),
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

    /***************************************************************************
                                   Nested pools
    ***************************************************************************/

    /// @inheritdoc ICompositeLiquidityRouter
    function addLiquidityUnbalancedNestedPool(
        address mainPool,
        NestedPoolAddOperation[] calldata nestedPoolOperations
    ) external saveSender(msg.sender) returns (uint256) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeWithSelector(
                        CompositeLiquidityRouter.addLiquidityUnbalancedNestedPoolHook.selector,
                        AddLiquidityNestedPoolHookParams({
                            pool: mainPool,
                            sender: msg.sender,
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
        NestedPoolAddOperation[] calldata nestedPoolOperations,
        address sender
    ) external saveSender(sender) returns (uint256) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeWithSelector(
                        CompositeLiquidityRouter.addLiquidityUnbalancedNestedPoolHook.selector,
                        AddLiquidityNestedPoolHookParams({
                            pool: mainPool,
                            sender: address(this),
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
        _fillNestedPoolAddOperationIndexByPoolMapping(params.nestedPoolOperations);

        return
            _addLiquidityUnbalancedNestedPool(
                params.pool,
                address(0),
                params.pool,
                params,
                EVMCallModeHelpers.isStaticCall()
            );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function removeLiquidityProportionalNestedPool(
        address mainPool,
        uint256 targetPoolExactBptAmountIn,
        uint256 expectedAmountOutCount,
        NestedPoolRemoveOperation[] calldata nestedPoolOperations
    ) external saveSender(msg.sender) returns (RemoveAmountOut[] memory totalAmountsOut) {
        totalAmountsOut = abi.decode(
            _vault.unlock(
                abi.encodeWithSelector(
                    CompositeLiquidityRouter.removeLiquidityProportionalNestedPoolHook.selector,
                    RemoveLiquidityNestedPoolHookParams({
                        sender: msg.sender,
                        pool: mainPool,
                        targetPoolExactBptAmountIn: targetPoolExactBptAmountIn,
                        expectedAmountOutCount: expectedAmountOutCount,
                        nestedPoolOperations: nestedPoolOperations
                    })
                )
            ),
            (RemoveAmountOut[])
        );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function queryRemoveLiquidityProportionalNestedPool(
        address mainPool,
        uint256 targetPoolExactBptAmountIn,
        uint256 expectedAmountOutCount,
        address sender,
        NestedPoolRemoveOperation[] calldata nestedPoolOperations
    ) external saveSender(sender) returns (RemoveAmountOut[] memory totalAmountsOut) {
        (totalAmountsOut) = abi.decode(
            _vault.quote(
                abi.encodeWithSelector(
                    CompositeLiquidityRouter.removeLiquidityProportionalNestedPoolHook.selector,
                    RemoveLiquidityNestedPoolHookParams({
                        sender: address(this),
                        pool: mainPool,
                        targetPoolExactBptAmountIn: targetPoolExactBptAmountIn,
                        expectedAmountOutCount: expectedAmountOutCount,
                        nestedPoolOperations: nestedPoolOperations
                    })
                )
            ),
            (RemoveAmountOut[])
        );
    }

    function removeLiquidityProportionalNestedPoolHook(
        RemoveLiquidityNestedPoolHookParams calldata params
    ) external nonReentrant onlyVault returns (RemoveAmountOut[] memory totalAmountsOut) {
        _fillNestedPoolRemoveOperationIndexByPoolMapping(params.nestedPoolOperations);

        RemoveLiquidityVars memory vars = RemoveLiquidityVars({
            mainPool: params.pool,
            sender: params.sender,
            isStaticCall: EVMCallModeHelpers.isStaticCall(),
            nestedPoolOperations: params.nestedPoolOperations,
            totalAmountsOut: new RemoveAmountOut[](params.expectedAmountOutCount),
            nextIndex: 0
        });
        _removeLiquidityProportionalNestedPool(address(0), params.pool, params.targetPoolExactBptAmountIn, vars);

        return vars.totalAmountsOut;
    }

    /***************************************************************************
                            Internal & Private functions
    ***************************************************************************/

    function _addLiquidityUnbalancedNestedPool(
        address mainPool,
        address prevPool,
        address pool,
        AddLiquidityNestedPoolHookParams calldata params,
        bool isStaticCall
    ) internal returns (uint256 bptAmountOut) {
        IERC20[] memory childTokens = _vault.getPoolTokens(pool);
        uint256[] memory childTokensAmountsIn = new uint256[](childTokens.length);

        (
            bool isPoolNestedPoolAddOperationExist,
            NestedPoolAddOperation memory nestedPoolOperation
        ) = _getNestedPoolAddOperationByPool(prevPool, pool, params.nestedPoolOperations);

        bool doNeedToAddLiquidityToPool = isPoolNestedPoolAddOperationExist;

        for (uint256 i = 0; i < childTokens.length; i++) {
            address childToken = address(childTokens[i]);

            if (_vault.isPoolRegistered(childToken)) {
                childTokensAmountsIn[i] = _addLiquidityUnbalancedNestedPool(
                    mainPool,
                    pool,
                    childToken,
                    params,
                    isStaticCall
                );
            } else if (_vault.isERC4626BufferInitialized(IERC4626(childToken))) {
                (
                    bool isERC4626PoolOperationExist,
                    NestedPoolAddOperation memory erc4626NestedPoolAddOperation
                ) = _getNestedPoolAddOperationByPool(pool, childToken, params.nestedPoolOperations);

                if (isERC4626PoolOperationExist) {
                    bool isStaticCall_ = isStaticCall; // Avoid stack too deep error
                    (, uint256 wrappedAmount) = _wrapToken(
                        params.sender,
                        IERC20(childToken),
                        // Only one token can be wrapped in ERC4626 pools
                        erc4626NestedPoolAddOperation.tokensInAmounts[0],
                        SwapKind.EXACT_IN,
                        0,
                        isStaticCall_,
                        erc4626NestedPoolAddOperation.wethIsEth
                    );
                    childTokensAmountsIn[i] = wrappedAmount;
                } else if (isPoolNestedPoolAddOperationExist && nestedPoolOperation.tokensInAmounts[i] > 0) {
                    childTokensAmountsIn[i] = nestedPoolOperation.tokensInAmounts[i];

                    if (isStaticCall == false) {
                        _takeTokenIn(params.sender, IERC20(childToken), childTokensAmountsIn[i], false);
                    }
                }
            } else if (isPoolNestedPoolAddOperationExist && nestedPoolOperation.tokensInAmounts[i] > 0) {
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
                minBptAmountOut: isPoolNestedPoolAddOperationExist ? nestedPoolOperation.minBptAmountOut : 0,
                kind: AddLiquidityKind.UNBALANCED,
                userData: isPoolNestedPoolAddOperationExist ? nestedPoolOperation.userData : new bytes(0)
            })
        );

        if (pool != mainPool && isStaticCall == false) {
            // // Since the BPT will be inserted into the parent pool, gets the credit from the inserted BPTs in
            // // advance
            _takeTokenIn(params.sender, IERC20(pool), bptAmountOut, false);
        }
    }

    function _removeLiquidityProportionalNestedPool(
        address prevPool,
        address pool,
        uint256 exactBptAmountIn,
        RemoveLiquidityVars memory removeLiquidityVars
    ) internal returns (uint256) {
        IERC20[] memory childTokens = _vault.getPoolTokens(pool);

        (
            bool isPoolNestedPoolRemoveOperationExist,
            NestedPoolRemoveOperation memory nestedPoolOperation
        ) = _getNestedPoolRemoveOperationByPool(prevPool, pool, removeLiquidityVars.nestedPoolOperations);
        if (isPoolNestedPoolRemoveOperationExist) {
            InputHelpers.ensureInputLengthMatch(nestedPoolOperation.minAmountsOut.length, childTokens.length);
        }

        (, uint256[] memory amountsOut, ) = _vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool,
                from: removeLiquidityVars.sender,
                maxBptAmountIn: exactBptAmountIn,
                minAmountsOut: isPoolNestedPoolRemoveOperationExist
                    ? nestedPoolOperation.minAmountsOut
                    : new uint256[](childTokens.length),
                kind: RemoveLiquidityKind.PROPORTIONAL,
                userData: nestedPoolOperation.userData
            })
        );

        for (uint256 i = 0; i < childTokens.length; i++) {
            address childToken = address(childTokens[i]);

            if (_vault.isPoolRegistered(childToken)) {
                if (removeLiquidityVars.isStaticCall == false) {
                    _sendTokenOut(removeLiquidityVars.sender, IERC20(childToken), amountsOut[i], false);
                }
                removeLiquidityVars.nextIndex = _removeLiquidityProportionalNestedPool(
                    pool,
                    childToken,
                    amountsOut[i],
                    removeLiquidityVars
                );
            } else if (_vault.isERC4626BufferInitialized(IERC4626(childToken))) {
                (
                    bool isNestedERC4626Operation,
                    NestedPoolRemoveOperation memory nestedERC4626Operation
                ) = _getNestedPoolRemoveOperationByPool(pool, childToken, removeLiquidityVars.nestedPoolOperations);

                bool isStaticCall_ = removeLiquidityVars.isStaticCall; // Avoid stack too deep error
                (uint256 underlyingAmount, , IERC20 underlyingToken) = _unwrapToken(
                    removeLiquidityVars.sender,
                    IERC20(childToken),
                    amountsOut[i],
                    isNestedERC4626Operation ? nestedERC4626Operation.minAmountsOut[0] : 0,
                    isStaticCall_,
                    nestedERC4626Operation.wethIsEth
                );

                address pool_ = pool; // Avoid stack too deep error
                removeLiquidityVars.totalAmountsOut[removeLiquidityVars.nextIndex] = RemoveAmountOut({
                    pool: pool_,
                    token: underlyingToken,
                    amountOut: underlyingAmount
                });
                removeLiquidityVars.nextIndex++;
            } else {
                if (removeLiquidityVars.isStaticCall == false) {
                    _sendTokenOut(removeLiquidityVars.sender, IERC20(childToken), amountsOut[i], false);
                }
                removeLiquidityVars.totalAmountsOut[removeLiquidityVars.nextIndex] = RemoveAmountOut({
                    token: IERC20(childToken),
                    amountOut: amountsOut[i],
                    pool: pool
                });
                removeLiquidityVars.nextIndex++;
            }
        }

        return removeLiquidityVars.nextIndex;
    }

    function _wrapToken(
        address sender,
        IERC20 erc4626PoolToken,
        uint256 amountIn,
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
                _takeTokenIn(sender, erc4626PoolToken, amountIn, wethIsEth);
            }

            return (amountIn, amountIn);
        }

        if (isStaticCall == false) {
            if (kind == SwapKind.EXACT_IN) {
                // If the SwapKind is EXACT_IN, take the exact amount in from the sender.
                _takeTokenIn(sender, underlyingToken, amountIn, wethIsEth);
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
                amountGivenRaw: amountIn,
                limitRaw: limit
            })
        );

        if (isStaticCall == false && kind == SwapKind.EXACT_OUT) {
            // If the SwapKind is EXACT_OUT, the limit of underlying tokens was taken from the user, so the
            // difference between limit and exact underlying amount needs to be returned to the sender.
            _vault.sendTo(underlyingToken, sender, limit - underlyingAmount);
        }
    }

    function _unwrapToken(
        address sender,
        IERC20 erc4626PoolToken,
        uint256 amountOut,
        uint256 minAmountOut,
        bool isStaticCall,
        bool wethIsEth
    ) private returns (uint256 underlyingAmount, uint256 wrappedAmount, IERC20 underlyingToken) {
        IERC4626 wrappedToken = IERC4626(address(erc4626PoolToken));
        underlyingToken = IERC20(_vault.getBufferAsset(wrappedToken));

        // If the Vault returns address 0 as underlying, it means that the ERC4626 token buffer was not
        // initialized. Thus, the Router treats it as a non-ERC4626 token.
        if (address(underlyingToken) == address(0)) {
            if (isStaticCall == false) {
                _sendTokenOut(sender, erc4626PoolToken, amountOut, wethIsEth);
            }
            return (amountOut, amountOut, erc4626PoolToken);
        }

        // `erc4626BufferWrapOrUnwrap` will fail if the wrappedToken is not ERC4626-conforming.
        (, , underlyingAmount) = _vault.erc4626BufferWrapOrUnwrap(
            BufferWrapOrUnwrapParams({
                kind: SwapKind.EXACT_IN,
                direction: WrappingDirection.UNWRAP,
                wrappedToken: wrappedToken,
                amountGivenRaw: amountOut,
                limitRaw: minAmountOut
            })
        );

        if (isStaticCall == false) {
            _sendTokenOut(sender, underlyingToken, underlyingAmount, wethIsEth);
        }
    }

    function _getNestedPoolAddOperationByPool(
        address prevPool,
        address pool,
        NestedPoolAddOperation[] calldata nestedPoolOperations
    ) private view returns (bool isExist, NestedPoolAddOperation memory parentNestedPoolAddOperation) {
        uint256 index = _nestedPoolOperationIndexByPoolMapping().tGet(keccak256(abi.encodePacked(prevPool, pool)));

        if (index != 0) {
            parentNestedPoolAddOperation = nestedPoolOperations[index - 1];
            isExist = true;
        }
    }

    function _fillNestedPoolAddOperationIndexByPoolMapping(
        NestedPoolAddOperation[] calldata nestedPoolOperations
    ) private {
        for (uint256 i = 0; i < nestedPoolOperations.length; i++) {
            bytes32 key = keccak256(abi.encodePacked(nestedPoolOperations[i].prevPool, nestedPoolOperations[i].pool));
            if (_nestedPoolOperationIndexByPoolMapping().tGet(key) != 0) {
                revert("Some nestedPoolOperations have the same pool");
            }

            _nestedPoolOperationIndexByPoolMapping().tSet(key, i + 1); // 0 is reserved for not found
        }
    }

    function _getNestedPoolRemoveOperationByPool(
        address prevPool,
        address pool,
        NestedPoolRemoveOperation[] memory nestedPoolOperations
    ) private view returns (bool isExist, NestedPoolRemoveOperation memory nestedPoolRemoveOperation) {
        uint256 index = _nestedPoolOperationIndexByPoolMapping().tGet(keccak256(abi.encodePacked(prevPool, pool)));

        if (index != 0) {
            nestedPoolRemoveOperation = nestedPoolOperations[index - 1];
            isExist = true;
        }
    }

    function _fillNestedPoolRemoveOperationIndexByPoolMapping(
        NestedPoolRemoveOperation[] calldata nestedPoolOperations
    ) private {
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
