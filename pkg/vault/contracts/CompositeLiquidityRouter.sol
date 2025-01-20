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

    // The level is 1-based, so the outermost pool (level 1) can contain a nested BPT, but any pool tokens in the child
    // pool (level 2) will not be expanded further, but simply treated as standard tokens.
    uint256 internal constant _MAX_LEVEL_IN_NESTED_OPERATIONS = 2;

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
        bptAmountOut = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    CompositeLiquidityRouter.addLiquidityERC4626PoolUnbalancedHook,
                    (
                        AddLiquidityHookParams({
                            sender: address(this),
                            pool: pool,
                            maxAmountsIn: exactAmountsIn,
                            minBptAmountOut: 0,
                            kind: AddLiquidityKind.UNBALANCED,
                            wethIsEth: false,
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
    function queryAddLiquidityProportionalToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (address[] memory tokensIn, uint256[] memory amountsIn) {
        (tokensIn, amountsIn) = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    CompositeLiquidityRouter.addLiquidityERC4626PoolProportionalHook,
                    (
                        AddLiquidityHookParams({
                            sender: address(this),
                            pool: pool,
                            maxAmountsIn: _maxTokenLimits(pool),
                            minBptAmountOut: exactBptAmountOut,
                            kind: AddLiquidityKind.PROPORTIONAL,
                            wethIsEth: false,
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
    function queryRemoveLiquidityProportionalFromERC4626Pool(
        address pool,
        bool[] memory unwrapWrapped,
        uint256 exactBptAmountIn,
        address sender,
        bytes memory userData
    ) external saveSender(sender) returns (address[] memory tokensOut, uint256[] memory amountsOut) {
        IERC20[] memory erc4626PoolTokens = _vault.getPoolTokens(pool);
        (tokensOut, amountsOut) = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    CompositeLiquidityRouter.removeLiquidityERC4626PoolProportionalHook,
                    (
                        RemoveLiquidityHookParams({
                            sender: address(this),
                            pool: pool,
                            minAmountsOut: new uint256[](erc4626PoolTokens.length),
                            maxBptAmountIn: exactBptAmountIn,
                            kind: RemoveLiquidityKind.PROPORTIONAL,
                            wethIsEth: false,
                            userData: userData
                        }),
                        unwrapWrapped
                    )
                )
            ),
            (address[], uint256[])
        );
    }

    function addLiquidityERC4626PoolUnbalancedHook(
        AddLiquidityHookParams calldata params,
        bool[] calldata wrapUnderlying
    ) external nonReentrant onlyVault returns (uint256 bptAmountOut) {
        IERC20[] memory erc4626PoolTokens = _vault.getPoolTokens(params.pool);
        uint256 poolTokensLength = erc4626PoolTokens.length;

        // Revert if `poolTokens` length does not match `maxAmountsIn` and `wrapUnderlying`.
        InputHelpers.ensureInputLengthMatch(poolTokensLength, params.maxAmountsIn.length, wrapUnderlying.length);

        uint256[] memory amountsIn = _wrapTokensExactInIfRequired(
            params.sender,
            wrapUnderlying,
            erc4626PoolTokens,
            params.maxAmountsIn,
            params.wethIsEth
        );

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

        (tokensIn, amountsIn) = _wrapTokensExactOutIfRequired(
            params.sender,
            wrapUnderlying,
            erc4626PoolTokens,
            wrappedAmountsIn,
            params.maxAmountsIn,
            params.wethIsEth
        );
    }

    function removeLiquidityERC4626PoolProportionalHook(
        RemoveLiquidityHookParams calldata params,
        bool[] calldata unwrapWrapped
    ) external nonReentrant onlyVault returns (address[] memory tokensOut, uint256[] memory amountsOut) {
        IERC20[] memory erc4626PoolTokens = _vault.getPoolTokens(params.pool);
        uint256 poolTokensLength = erc4626PoolTokens.length;

        // Revert if `poolTokens` length does not match `minAmountsOut` and `unwrapWrapped`.
        InputHelpers.ensureInputLengthMatch(poolTokensLength, params.minAmountsOut.length, unwrapWrapped.length);

        amountsOut = new uint256[](poolTokensLength);

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

        tokensOut = new address[](poolTokensLength);
        for (uint256 i = 0; i < poolTokensLength; ++i) {
            IERC4626 wrappedToken = IERC4626(address(erc4626PoolTokens[i]));
            IERC20 underlyingToken = IERC20(_vault.getBufferAsset(wrappedToken));

            if (unwrapWrapped[i]) {
                if (address(underlyingToken) == address(0)) {
                    revert IVaultErrors.BufferNotInitialized(wrappedToken);
                }

                // `erc4626BufferWrapOrUnwrap` will fail if the wrappedToken is not ERC4626-conforming.
                (, , amountsOut[i]) = _vault.erc4626BufferWrapOrUnwrap(
                    BufferWrapOrUnwrapParams({
                        kind: SwapKind.EXACT_IN,
                        direction: WrappingDirection.UNWRAP,
                        wrappedToken: wrappedToken,
                        amountGivenRaw: wrappedAmountsOut[i],
                        limitRaw: params.minAmountsOut[i]
                    })
                );
                tokensOut[i] = address(underlyingToken);

                if (isStaticCall == false) {
                    _sendTokenOut(params.sender, underlyingToken, amountsOut[i], params.wethIsEth);
                }
            } else {
                amountsOut[i] = wrappedAmountsOut[i];
                tokensOut[i] = address(wrappedToken);

                if (isStaticCall == false) {
                    _sendTokenOut(params.sender, erc4626PoolTokens[i], amountsOut[i], params.wethIsEth);
                }
            }

            if (amountsOut[i] < params.minAmountsOut[i]) {
                revert IVaultErrors.AmountOutBelowMin(IERC20(tokensOut[i]), amountsOut[i], params.minAmountsOut[i]);
            }
        }
    }

    /// @dev Assumes array lengths have been checked externally.
    function _wrapTokensExactInIfRequired(
        address sender,
        bool[] memory wrapUnderlying,
        IERC20[] memory erc4626PoolTokens,
        uint256[] memory amountsIn,
        bool wethIsEth
    ) private returns (uint256[] memory wrappedAmountsIn) {
        uint256 poolTokensLength = erc4626PoolTokens.length;
        wrappedAmountsIn = new uint256[](poolTokensLength);

        bool isStaticCall = EVMCallModeHelpers.isStaticCall();

        for (uint256 i = 0; i < poolTokensLength; ++i) {
            // Treat all ERC4626 pool tokens as wrapped. The next step will verify if we can use the wrappedToken as
            // a valid ERC4626.
            IERC4626 wrappedToken = IERC4626(address(erc4626PoolTokens[i]));
            IERC20 underlyingToken = IERC20(_vault.getBufferAsset(wrappedToken));

            // Check whether the caller wants to use the token as an ERC4626 (i.e., wrap/unwrap it), or just use it as
            // a standard token.
            if (wrapUnderlying[i]) {
                if (address(underlyingToken) == address(0)) {
                    revert IVaultErrors.BufferNotInitialized(wrappedToken);
                }

                uint256 wrappedAmount;
                if (amountsIn[i] > 0) {
                    if (isStaticCall == false) {
                        // Take the exact amount in from the sender.
                        _takeTokenIn(sender, underlyingToken, amountsIn[i], wethIsEth);
                    }

                    // `erc4626BufferWrapOrUnwrap` will fail if the wrappedToken isn't ERC4626-conforming.
                    (, , wrappedAmount) = _vault.erc4626BufferWrapOrUnwrap(
                        BufferWrapOrUnwrapParams({
                            kind: SwapKind.EXACT_IN,
                            direction: WrappingDirection.WRAP,
                            wrappedToken: wrappedToken,
                            amountGivenRaw: amountsIn[i],
                            limitRaw: 0
                        })
                    );
                }

                wrappedAmountsIn[i] = wrappedAmount;
            } else {
                wrappedAmountsIn[i] = amountsIn[i];

                if (isStaticCall == false) {
                    _takeTokenIn(sender, wrappedToken, wrappedAmountsIn[i], wethIsEth);
                }
            }
        }

        // If there's a leftover of eth, send it back to the sender. The router should not keep ETH.
        _returnEth(sender);
    }

    /// @dev Assumes array lengths have been checked externally.
    function _wrapTokensExactOutIfRequired(
        address sender,
        bool[] memory wrapUnderlying,
        IERC20[] memory erc4626PoolTokens,
        uint256[] memory wrappedAmountsIn,
        uint256[] memory maxAmountsIn,
        bool wethIsEth
    ) private returns (address[] memory tokensIn, uint256[] memory amountsIn) {
        uint256 poolTokensLength = erc4626PoolTokens.length;
        amountsIn = new uint256[](poolTokensLength);

        bool isStaticCall = EVMCallModeHelpers.isStaticCall();

        tokensIn = new address[](poolTokensLength);

        for (uint256 i = 0; i < poolTokensLength; ++i) {
            // Treat all ERC4626 pool tokens as wrapped. The next step will verify if we can use the wrappedToken as
            // a valid ERC4626.
            IERC4626 wrappedToken = IERC4626(address(erc4626PoolTokens[i]));
            IERC20 underlyingToken = IERC20(_vault.getBufferAsset(wrappedToken));

            // Check whether the caller wants to use the token as an ERC4626 (i.e., wrap/unwrap it), or just use it as
            // a standard token.
            if (wrapUnderlying[i]) {
                if (address(underlyingToken) == address(0)) {
                    revert IVaultErrors.BufferNotInitialized(wrappedToken);
                }

                uint256 underlyingAmount;
                if (wrappedAmountsIn[i] > 0) {
                    if (isStaticCall == false) {
                        // The exact amount in is not known, because we have only
                        // wrappedAmountsIn. Therefore, take the maxAmountsIn. After the wrap operation, the difference
                        // between the maxAmountsIn and the actual underlying amount is returned to the sender.
                        _takeTokenIn(sender, underlyingToken, maxAmountsIn[i], wethIsEth);
                    }

                    // `erc4626BufferWrapOrUnwrap` will fail if the wrappedToken isn't ERC4626-conforming.
                    (, underlyingAmount, ) = _vault.erc4626BufferWrapOrUnwrap(
                        BufferWrapOrUnwrapParams({
                            kind: SwapKind.EXACT_OUT,
                            direction: WrappingDirection.WRAP,
                            wrappedToken: wrappedToken,
                            amountGivenRaw: wrappedAmountsIn[i],
                            limitRaw: maxAmountsIn[i]
                        })
                    );
                }

                if (isStaticCall == false) {
                    // The maxAmountsIn of underlying tokens was taken from the user, so the
                    // difference between maxAmountsIn and exact underlying amount needs to be returned to the sender.
                    _sendTokenOut(sender, underlyingToken, maxAmountsIn[i] - underlyingAmount, wethIsEth);
                }

                amountsIn[i] = underlyingAmount;
                tokensIn[i] = address(underlyingToken);
            } else {
                if (isStaticCall == false) {
                    _takeTokenIn(sender, wrappedToken, wrappedAmountsIn[i], wethIsEth);
                }

                amountsIn[i] = wrappedAmountsIn[i];
                tokensIn[i] = address(wrappedToken);
            }

            if (amountsIn[i] > maxAmountsIn[i]) {
                revert IVaultErrors.AmountInAboveMax(IERC20(tokensIn[i]), amountsIn[i], maxAmountsIn[i]);
            }
        }

        // If there's a leftover of eth, send it back to the sender. The router should not keep ETH.
        _returnEth(sender);
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
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        CompositeLiquidityRouter.addLiquidityUnbalancedNestedPoolHook,
                        (
                            AddLiquidityHookParams({
                                pool: parentPool,
                                sender: address(this),
                                maxAmountsIn: exactAmountsIn,
                                minBptAmountOut: 0,
                                kind: AddLiquidityKind.UNBALANCED,
                                wethIsEth: false,
                                userData: userData
                            }),
                            tokensIn
                        )
                    )
                ),
                (uint256)
            );
    }

    function addLiquidityUnbalancedNestedPoolHook(
        AddLiquidityHookParams calldata params,
        address[] memory tokensIn
    ) external nonReentrant onlyVault returns (uint256 exactBptAmountOut) {
        // Revert if tokensIn length does not match with maxAmountsIn length.
        InputHelpers.ensureInputLengthMatch(params.maxAmountsIn.length, tokensIn.length);

        bool isStaticCall = EVMCallModeHelpers.isStaticCall();

        // Loads a Set with all amounts to be inserted in the nested pools, so we don't need to iterate in the tokens
        // array to find the child pool amounts to insert.
        for (uint256 i = 0; i < tokensIn.length; ++i) {
            if (params.maxAmountsIn[i] == 0) {
                continue;
            }

            _currentSwapTokenInAmounts().tSet(tokensIn[i], params.maxAmountsIn[i]);
            _currentSwapTokensIn().add(tokensIn[i]);
        }

        (uint256[] memory amountsIn, ) = _addLiquidity(params.pool, params);

        // Adds liquidity to the parent pool, mints parentPool's BPT to the sender and checks the minimum BPT out.
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

    function _addLiquidity(
        address pool,
        AddLiquidityHookParams calldata params
    ) internal returns (uint256[] memory amountsIn, bool allAmountsEmpty) {
        return _addLiquidityRecursive(pool, params, 1);
    }

    function _addLiquidityRecursive(
        address currentPool,
        AddLiquidityHookParams calldata params,
        uint256 level
    ) internal returns (uint256[] memory amountsIn, bool allAmountsEmpty) {
        allAmountsEmpty = true;

        IERC20[] memory parentPoolTokens = _vault.getPoolTokens(currentPool);
        amountsIn = new uint256[](parentPoolTokens.length);

        // Iterate over each token of the parent pool. If it's a BPT, add liquidity unbalanced to it.
        for (uint256 i = 0; i < parentPoolTokens.length; i++) {
            address childToken = address(parentPoolTokens[i]);

            // NOTE: Recursion involving a pool containing its own BPT is explicitly prohibited by the Vault.
            // This case is impossible and does not require handling.

            if (_vault.isPoolRegistered(childToken)) {
                // Token is a BPT, so add liquidity to the child pool.

                if (level > _MAX_LEVEL_IN_NESTED_OPERATIONS) {
                    // If we have exceeded the maximum level of nested operations,
                    // the token will be considered a standard ERC20.
                    if (_settledTokenAmounts().tGet(childToken) == 0) {
                        amountsIn[i] = _currentSwapTokenInAmounts().tGet(childToken);
                        _settledTokenAmounts().tSet(childToken, amountsIn[i]);
                    }
                    continue;
                }

                address nextPool = childToken;
                (uint256[] memory childPoolAmountsIn, bool childPoolAmountsEmpty) = _addLiquidityRecursive(
                    nextPool,
                    params,
                    level + 1
                );

                if (childPoolAmountsEmpty == false) {
                    // Add Liquidity will mint childTokens to the Vault, so the insertion of liquidity in the parent
                    // pool will be a logic insertion, not a token transfer.
                    (, uint256 exactChildBptAmountOut, ) = _vault.addLiquidity(
                        AddLiquidityParams({
                            pool: childToken,
                            to: address(_vault),
                            maxAmountsIn: childPoolAmountsIn,
                            minBptAmountOut: 0,
                            kind: params.kind,
                            userData: params.userData
                        })
                    );

                    amountsIn[i] = exactChildBptAmountOut;

                    // Since the BPT will be inserted into the parent pool, gets the credit from the inserted BPTs in
                    // advance.
                    _vault.settle(IERC20(childToken), exactChildBptAmountOut);
                }
            } else if (
                _vault.isERC4626BufferInitialized(IERC4626(childToken)) &&
                _currentSwapTokenInAmounts().tGet(childToken) == 0 // wrapped amount in was not specified
            ) {
                // The ERC4626 token has a buffer initialized within the Vault. Additionally, since the sender did not
                // specify an input amount for the wrapped token, the function will wrap the underlying asset and use
                // the resulting wrapped tokens to add liquidity to the pool.
                amountsIn[i] = _wrapAndUpdateTokenInAmounts(IERC4626(childToken), params.sender, params.wethIsEth);
            } else if (_settledTokenAmounts().tGet(childToken) == 0) {
                // Set this token's amountIn if it's a standard token that was not previously settled.
                amountsIn[i] = _currentSwapTokenInAmounts().tGet(childToken);
                _settledTokenAmounts().tSet(childToken, amountsIn[i]);
            }

            if (amountsIn[i] > 0) {
                allAmountsEmpty = false;
            }
        }
    }

    /**
     * @notice Wraps the underlying tokens specified in the transient set `_currentSwapTokenInAmounts`, and updates
     * this set with the resulting amount of wrapped tokens from the operation.
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
        (amountsOut) = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    CompositeLiquidityRouter.removeLiquidityProportionalNestedPoolHook,
                    (
                        RemoveLiquidityHookParams({
                            sender: address(this),
                            pool: parentPool,
                            minAmountsOut: new uint256[](tokensOut.length),
                            maxBptAmountIn: exactBptAmountIn,
                            kind: RemoveLiquidityKind.PROPORTIONAL,
                            wethIsEth: false,
                            userData: userData
                        }),
                        tokensOut
                    )
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
            _settlePaths(params.sender, params.wethIsEth);
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
        address underlyingToken = _vault.getERC4626BufferAsset(wrappedToken);
        _currentSwapTokensOut().add(underlyingToken);
        _currentSwapTokenOutAmounts().tAdd(underlyingToken, underlyingAmountOut);
    }
}
