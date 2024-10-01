// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

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
    TransientStorageHelpers
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

    constructor(IVault vault, IWETH weth, IPermit2 permit2) BatchRouterCommon(vault, weth, permit2) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /*******************************************************************************
                                ERC4626 Pools
    *******************************************************************************/

    /// @inheritdoc ICompositeLiquidityRouter
    function addLiquidityUnbalancedToERC4626Pool(
        address pool,
        uint256[] memory exactUnderlyingAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender returns (uint256 bptAmountOut) {
        bptAmountOut = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    CompositeLiquidityRouter.addLiquidityERC4626PoolUnbalancedHook,
                    AddLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        maxAmountsIn: exactUnderlyingAmountsIn,
                        minBptAmountOut: minBptAmountOut,
                        kind: AddLiquidityKind.UNBALANCED,
                        wethIsEth: wethIsEth,
                        userData: userData
                    })
                )
            ),
            (uint256)
        );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function addLiquidityProportionalToERC4626Pool(
        address pool,
        uint256[] memory maxUnderlyingAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender returns (uint256[] memory underlyingAmountsIn) {
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
    ) external payable saveSender returns (uint256[] memory underlyingAmountsOut) {
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
    function queryAddLiquidityUnbalancedToERC4626Pool(
        address pool,
        uint256[] memory exactUnderlyingAmountsIn,
        bytes memory userData
    ) external saveSender returns (uint256 bptAmountOut) {
        bptAmountOut = abi.decode(
            _vault.quote(
                abi.encodeCall(
                    CompositeLiquidityRouter.addLiquidityERC4626PoolUnbalancedHook,
                    AddLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        maxAmountsIn: exactUnderlyingAmountsIn,
                        minBptAmountOut: 0,
                        kind: AddLiquidityKind.UNBALANCED,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256)
        );
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function queryAddLiquidityProportionalToERC4626Pool(
        address pool,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) external saveSender returns (uint256[] memory underlyingAmountsIn) {
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
        bytes memory userData
    ) external saveSender returns (uint256[] memory underlyingAmountsOut) {
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

    function addLiquidityERC4626PoolUnbalancedHook(
        AddLiquidityHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256 bptAmountOut) {
        IERC20[] memory erc4626PoolTokens = _vault.getPoolTokens(params.pool);
        (, uint256[] memory wrappedAmountsIn) = _wrapTokens(
            params,
            erc4626PoolTokens,
            params.maxAmountsIn,
            SwapKind.EXACT_IN,
            new uint256[](erc4626PoolTokens.length)
        );

        // Add wrapped amounts to the ERC4626 pool.
        (, bptAmountOut, ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: params.pool,
                to: params.sender,
                maxAmountsIn: wrappedAmountsIn,
                minBptAmountOut: params.minBptAmountOut,
                kind: params.kind,
                userData: params.userData
            })
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

        (underlyingAmountsIn, ) = _wrapTokens(
            params,
            erc4626PoolTokens,
            wrappedAmountsIn,
            SwapKind.EXACT_OUT,
            params.maxAmountsIn
        );
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

    function _wrapTokens(
        AddLiquidityHookParams calldata params,
        IERC20[] memory erc4626PoolTokens,
        uint256[] memory amountsIn,
        SwapKind kind,
        uint256[] memory limits
    ) private returns (uint256[] memory underlyingAmounts, uint256[] memory wrappedAmounts) {
        uint256 poolTokensLength = erc4626PoolTokens.length;
        underlyingAmounts = new uint256[](poolTokensLength);
        wrappedAmounts = new uint256[](poolTokensLength);

        bool isStaticCall = EVMCallModeHelpers.isStaticCall();

        // Wrap given underlying tokens for wrapped tokens.
        for (uint256 i = 0; i < poolTokensLength; ++i) {
            // Treat all ERC4626 pool tokens as wrapped. The next step will verify if we can use the wrappedToken as
            // a valid ERC4626.
            IERC4626 wrappedToken = IERC4626(address(erc4626PoolTokens[i]));
            IERC20 underlyingToken = IERC20(_vault.getBufferAsset(wrappedToken));

            // If the Vault returns address 0 as underlying, it means that the ERC4626 token buffer was not
            // initialized. Thus, the Router treats it as a non-ERC4626 token.
            if (address(underlyingToken) == address(0)) {
                underlyingAmounts[i] = amountsIn[i];
                wrappedAmounts[i] = amountsIn[i];

                if (isStaticCall == false) {
                    _takeTokenIn(params.sender, erc4626PoolTokens[i], amountsIn[i], params.wethIsEth);
                }

                continue;
            }

            if (isStaticCall == false) {
                if (kind == SwapKind.EXACT_IN) {
                    // If the SwapKind is EXACT_IN, take the exact amount in from the sender.
                    _takeTokenIn(params.sender, underlyingToken, amountsIn[i], params.wethIsEth);
                } else {
                    // If the SwapKind is EXACT_OUT, the exact amount in is not known, because amountsIn is the
                    // amount of wrapped tokens. Therefore, take the limit. After the wrap operation, the difference
                    // between the limit and the actual underlying amount is returned to the sender.
                    _takeTokenIn(params.sender, underlyingToken, limits[i], params.wethIsEth);
                }
            }

            // `erc4626BufferWrapOrUnwrap` will fail if the wrappedToken isn't ERC4626-conforming.
            (, underlyingAmounts[i], wrappedAmounts[i]) = _vault.erc4626BufferWrapOrUnwrap(
                BufferWrapOrUnwrapParams({
                    kind: kind,
                    direction: WrappingDirection.WRAP,
                    wrappedToken: wrappedToken,
                    amountGivenRaw: amountsIn[i],
                    limitRaw: limits[i]
                })
            );

            if (isStaticCall == false && kind == SwapKind.EXACT_OUT) {
                // If the SwapKind is EXACT_OUT, the limit of underlying tokens was taken from the user, so the
                // difference between limit and exact underlying amount needs to be returned to the sender.
                _vault.sendTo(underlyingToken, params.sender, limits[i] - underlyingAmounts[i]);
            }
        }
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
        bytes memory userData
    ) external returns (uint256) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeWithSelector(
                        CompositeLiquidityRouter.addLiquidityUnbalancedNestedPoolHook.selector,
                        AddLiquidityHookParams({
                            pool: parentPool,
                            sender: msg.sender,
                            maxAmountsIn: exactAmountsIn,
                            minBptAmountOut: minBptAmountOut,
                            kind: AddLiquidityKind.UNBALANCED,
                            wethIsEth: false,
                            userData: userData
                        }),
                        tokensIn
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

        // Loads a Set with all amounts to be inserted in the nested pools, so we don't need to iterate in the tokens
        // array to find the child pool amounts to insert.
        for (uint256 i = 0; i < tokensIn.length; ++i) {
            _currentSwapTokenInAmounts().tSet(tokensIn[i], params.maxAmountsIn[i]);
        }

        IERC20[] memory parentPoolTokens = _vault.getPoolTokens(params.pool);

        // Iterate over each token of the parent pool. If it's a BPT, add liquidity unbalanced to it.
        for (uint256 i = 0; i < parentPoolTokens.length; i++) {
            address childToken = address(parentPoolTokens[i]);

            if (_vault.isPoolRegistered(childToken)) {
                // Token is a BPT, so add liquidity to the child pool.

                IERC20[] memory childPoolTokens = _vault.getPoolTokens(childToken);
                uint256[] memory childPoolAmountsIn = _getPoolAmountsIn(childPoolTokens);

                // Add Liquidity will mint childTokens to the Vault, so the insertion of liquidity in the parent pool
                // will be a logic insertion, not a token transfer.
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

                // Sets the amount in of child BPT to the exactBptAmountOut of the child pool, so all the minted BPT
                // will be added to the parent pool.
                _currentSwapTokenInAmounts().tSet(childToken, exactChildBptAmountOut);

                // Since the BPT will be inserted into the parent pool, gets the credit from the inserted BPTs in
                // advance.
                _vault.settle(IERC20(childToken), exactChildBptAmountOut);
            } else if (
                _vault.isERC4626BufferInitialized(IERC4626(childToken)) &&
                _currentSwapTokenInAmounts().tGet(childToken) == 0
            ) {
                // Token is an ERC4626 supported by the vault and the user did not add wrapped liquidity
                // directly, so wrap underlying and add wrapped liquidity to the pool.
                _wrapAndUpdateTokenInAmounts(IERC4626(childToken));
            }
        }

        uint256[] memory parentPoolAmountsIn = _getPoolAmountsIn(parentPoolTokens);

        // Adds liquidity to the parent pool, mints parentPool's BPT to the sender and checks the minimum BPT out.
        (, exactBptAmountOut, ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: params.pool,
                to: params.sender,
                maxAmountsIn: parentPoolAmountsIn,
                minBptAmountOut: params.minBptAmountOut,
                kind: params.kind,
                userData: params.userData
            })
        );

        // Since all values from _currentSwapTokenInAmounts are erased, recreates the set of amounts in so
        // `_settlePaths()` can charge the sender.
        for (uint256 i = 0; i < tokensIn.length; ++i) {
            _currentSwapTokensIn().add(tokensIn[i]);
            _currentSwapTokenInAmounts().tSet(tokensIn[i], params.maxAmountsIn[i]);
        }

        // Settle the amounts in.
        _settlePaths(params.sender, false);
    }

    function _getPoolAmountsIn(IERC20[] memory poolTokens) private returns (uint256[] memory poolAmountsIn) {
        poolAmountsIn = new uint256[](poolTokens.length);

        for (uint256 j = 0; j < poolTokens.length; j++) {
            address poolToken = address(poolTokens[j]);
            if (
                _vault.isERC4626BufferInitialized(IERC4626(poolToken)) &&
                _currentSwapTokenInAmounts().tGet(poolToken) == 0
            ) {
                // Token is an ERC4626 supported by the vault and the user did not add wrapped liquidity
                // directly, so wrap underlying and add wrapped liquidity to the pool.
                uint256 wrappedAmount = _wrapAndUpdateTokenInAmounts(IERC4626(poolToken));
                poolAmountsIn[j] = wrappedAmount;
            } else {
                poolAmountsIn[j] = _currentSwapTokenInAmounts().tGet(poolToken);
                // This operation does not support adding liquidity multiple times to the same token. So, we set
                // the amount in of the child pool token to 0. If the same token appears more times, the amount in
                // will be 0 for any other pool.
                _currentSwapTokenInAmounts().tSet(poolToken, 0);
            }
        }
    }

    function _wrapAndUpdateTokenInAmounts(IERC4626 wrappedToken) private returns (uint256 wrappedAmountOut) {
        address underlyingToken = wrappedToken.asset();
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

        _currentSwapTokenInAmounts().tSet(address(wrappedToken), wrappedAmountOut);
        _currentSwapTokenInAmounts().tSet(underlyingToken, 0);
        _vault.settle(IERC20(address(wrappedToken)), wrappedAmountOut);
    }

    /// @inheritdoc ICompositeLiquidityRouter
    function removeLiquidityProportionalNestedPool(
        address parentPool,
        uint256 exactBptAmountIn,
        address[] memory tokensOut,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut) {
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

    function removeLiquidityProportionalNestedPoolHook(
        RemoveLiquidityHookParams calldata params,
        address[] memory tokensOut
    ) external nonReentrant onlyVault returns (uint256[] memory amountsOut) {
        IERC20[] memory parentPoolTokens = _vault.getPoolTokens(params.pool);

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

        _settlePaths(params.sender, false);
    }

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

        address underlyingToken = wrappedToken.asset();
        _currentSwapTokensOut().add(underlyingToken);
        _currentSwapTokenOutAmounts().tAdd(underlyingToken, underlyingAmountOut);
    }
}
