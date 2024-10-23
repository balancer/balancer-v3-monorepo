// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Proxy } from "@openzeppelin/contracts/proxy/Proxy.sol";

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IRouterMain } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterMain.sol";
import { IRouterExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterExtension.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

import { RouterCommon } from "./RouterCommon.sol";

/**
 * @notice Entrypoint for swaps, liquidity operations, and corresponding queries.
 * @dev The external API functions unlock the Vault, which calls back into the corresponding hook functions.
 * These interact with the Vault, transfer tokens, settle accounting, and handle wrapping and unwrapping ETH.
 */
contract Router is IRouterMain, RouterCommon, ReentrancyGuardTransient, Proxy {
    using Address for address payable;
    using SafeCast for *;

    // Local reference to the Proxy pattern Router extension contract.
    IRouterExtension private immutable _routerExtension;

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2,
        IRouterExtension routerExtension
    ) RouterCommon(vault, weth, permit2) {
        _routerExtension = routerExtension;
    }

    /*******************************************************************************
                                Pool Initialization
    *******************************************************************************/

    /// @inheritdoc IRouterMain
    function initialize(
        address pool,
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        Router.initializeHook,
                        InitializeHookParams({
                            sender: msg.sender,
                            pool: pool,
                            tokens: tokens,
                            exactAmountsIn: exactAmountsIn,
                            minBptAmountOut: minBptAmountOut,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    /// @inheritdoc IRouterMain
    function initializeHook(
        InitializeHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256 bptAmountOut) {
        bptAmountOut = _vault.initialize(
            params.pool,
            params.sender,
            params.tokens,
            params.exactAmountsIn,
            params.minBptAmountOut,
            params.userData
        );

        for (uint256 i = 0; i < params.tokens.length; ++i) {
            IERC20 token = params.tokens[i];
            uint256 amountIn = params.exactAmountsIn[i];

            if (amountIn == 0) {
                continue;
            }

            // There can be only one WETH token in the pool.
            if (params.wethIsEth && address(token) == address(_weth)) {
                if (address(this).balance < amountIn) {
                    revert InsufficientEth();
                }

                _weth.deposit{ value: amountIn }();
                // Transfer WETH from the Router to the Vault.
                _weth.transfer(address(_vault), amountIn);
                _vault.settle(_weth, amountIn);
            } else {
                // Transfer tokens from the user to the Vault.
                // Any value over MAX_UINT128 would revert above in `initialize`, so this SafeCast shouldn't be
                // necessary. Done out of an abundance of caution.
                _permit2.transferFrom(params.sender, address(_vault), amountIn.toUint160(), address(token));
                _vault.settle(token, amountIn);
            }
        }

        // Return ETH dust.
        _returnEth(params.sender);
    }

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    /// @inheritdoc IRouterMain
    function addLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256[] memory amountsIn) {
        (amountsIn, , ) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    Router.addLiquidityHook,
                    AddLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        maxAmountsIn: maxAmountsIn,
                        minBptAmountOut: exactBptAmountOut,
                        kind: AddLiquidityKind.PROPORTIONAL,
                        wethIsEth: wethIsEth,
                        userData: userData
                    })
                )
            ),
            (uint256[], uint256, bytes)
        );
    }

    /// @inheritdoc IRouterMain
    function addLiquidityUnbalanced(
        address pool,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256 bptAmountOut) {
        (, bptAmountOut, ) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    Router.addLiquidityHook,
                    AddLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        maxAmountsIn: exactAmountsIn,
                        minBptAmountOut: minBptAmountOut,
                        kind: AddLiquidityKind.UNBALANCED,
                        wethIsEth: wethIsEth,
                        userData: userData
                    })
                )
            ),
            (uint256[], uint256, bytes)
        );
    }

    /// @inheritdoc IRouterMain
    function addLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        uint256 maxAmountIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256 amountIn) {
        (uint256[] memory maxAmountsIn, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
            pool,
            tokenIn,
            maxAmountIn
        );

        (uint256[] memory amountsIn, , ) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    Router.addLiquidityHook,
                    AddLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        maxAmountsIn: maxAmountsIn,
                        minBptAmountOut: exactBptAmountOut,
                        kind: AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                        wethIsEth: wethIsEth,
                        userData: userData
                    })
                )
            ),
            (uint256[], uint256, bytes)
        );

        return amountsIn[tokenIndex];
    }

    /// @inheritdoc IRouterMain
    function donate(
        address pool,
        uint256[] memory amountsIn,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) {
        _vault.unlock(
            abi.encodeCall(
                Router.addLiquidityHook,
                AddLiquidityHookParams({
                    sender: msg.sender,
                    pool: pool,
                    maxAmountsIn: amountsIn,
                    minBptAmountOut: 0,
                    kind: AddLiquidityKind.DONATION,
                    wethIsEth: wethIsEth,
                    userData: userData
                })
            )
        );
    }

    /// @inheritdoc IRouterMain
    function addLiquidityCustom(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    )
        external
        payable
        saveSender(msg.sender)
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData)
    {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        Router.addLiquidityHook,
                        AddLiquidityHookParams({
                            sender: msg.sender,
                            pool: pool,
                            maxAmountsIn: maxAmountsIn,
                            minBptAmountOut: minBptAmountOut,
                            kind: AddLiquidityKind.CUSTOM,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256[], uint256, bytes)
            );
    }

    /// @inheritdoc IRouterMain
    function addLiquidityHook(
        AddLiquidityHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData)
    {
        (amountsIn, bptAmountOut, returnData) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: params.pool,
                to: params.sender,
                maxAmountsIn: params.maxAmountsIn,
                minBptAmountOut: params.minBptAmountOut,
                kind: params.kind,
                userData: params.userData
            })
        );

        // maxAmountsIn length is checked against tokens length at the Vault.
        IERC20[] memory tokens = _vault.getPoolTokens(params.pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 amountIn = amountsIn[i];

            if (amountIn == 0) {
                continue;
            }

            // There can be only one WETH token in the pool.
            if (params.wethIsEth && address(token) == address(_weth)) {
                if (address(this).balance < amountIn) {
                    revert InsufficientEth();
                }

                _weth.deposit{ value: amountIn }();
                _weth.transfer(address(_vault), amountIn);
                _vault.settle(_weth, amountIn);
            } else {
                // Any value over MAX_UINT128 would revert above in `addLiquidity`, so this SafeCast shouldn't be
                // necessary. Done out of an abundance of caution.
                _permit2.transferFrom(params.sender, address(_vault), amountIn.toUint160(), address(token));
                _vault.settle(token, amountIn);
            }
        }

        // Send remaining ETH to the user.
        _returnEth(params.sender);
    }

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    /// @inheritdoc IRouterMain
    function removeLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256[] memory amountsOut) {
        (, amountsOut, ) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    Router.removeLiquidityHook,
                    RemoveLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        minAmountsOut: minAmountsOut,
                        maxBptAmountIn: exactBptAmountIn,
                        kind: RemoveLiquidityKind.PROPORTIONAL,
                        wethIsEth: wethIsEth,
                        userData: userData
                    })
                )
            ),
            (uint256, uint256[], bytes)
        );
    }

    /// @inheritdoc IRouterMain
    function removeLiquiditySingleTokenExactIn(
        address pool,
        uint256 exactBptAmountIn,
        IERC20 tokenOut,
        uint256 minAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256 amountOut) {
        (uint256[] memory minAmountsOut, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
            pool,
            tokenOut,
            minAmountOut
        );

        (, uint256[] memory amountsOut, ) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    Router.removeLiquidityHook,
                    RemoveLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        minAmountsOut: minAmountsOut,
                        maxBptAmountIn: exactBptAmountIn,
                        kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                        wethIsEth: wethIsEth,
                        userData: userData
                    })
                )
            ),
            (uint256, uint256[], bytes)
        );

        return amountsOut[tokenIndex];
    }

    /// @inheritdoc IRouterMain
    function removeLiquiditySingleTokenExactOut(
        address pool,
        uint256 maxBptAmountIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender(msg.sender) returns (uint256 bptAmountIn) {
        (uint256[] memory minAmountsOut, ) = _getSingleInputArrayAndTokenIndex(pool, tokenOut, exactAmountOut);

        (bptAmountIn, , ) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    Router.removeLiquidityHook,
                    RemoveLiquidityHookParams({
                        sender: msg.sender,
                        pool: pool,
                        minAmountsOut: minAmountsOut,
                        maxBptAmountIn: maxBptAmountIn,
                        kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                        wethIsEth: wethIsEth,
                        userData: userData
                    })
                )
            ),
            (uint256, uint256[], bytes)
        );

        return bptAmountIn;
    }

    /// @inheritdoc IRouterMain
    function removeLiquidityCustom(
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    )
        external
        payable
        saveSender(msg.sender)
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData)
    {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        Router.removeLiquidityHook,
                        RemoveLiquidityHookParams({
                            sender: msg.sender,
                            pool: pool,
                            minAmountsOut: minAmountsOut,
                            maxBptAmountIn: maxBptAmountIn,
                            kind: RemoveLiquidityKind.CUSTOM,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256, uint256[], bytes)
            );
    }

    /// @inheritdoc IRouterMain
    function removeLiquidityRecovery(
        address pool,
        uint256 exactBptAmountIn
    ) external payable returns (uint256[] memory amountsOut) {
        amountsOut = abi.decode(
            _vault.unlock(abi.encodeCall(Router.removeLiquidityRecoveryHook, (pool, msg.sender, exactBptAmountIn))),
            (uint256[])
        );
    }

    /// @inheritdoc IRouterMain
    function removeLiquidityHook(
        RemoveLiquidityHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData)
    {
        (bptAmountIn, amountsOut, returnData) = _vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: params.pool,
                from: params.sender,
                maxBptAmountIn: params.maxBptAmountIn,
                minAmountsOut: params.minAmountsOut,
                kind: params.kind,
                userData: params.userData
            })
        );

        // minAmountsOut length is checked against tokens length at the Vault.
        IERC20[] memory tokens = _vault.getPoolTokens(params.pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amountOut = amountsOut[i];
            if (amountOut == 0) {
                continue;
            }

            IERC20 token = tokens[i];

            // There can be only one WETH token in the pool.
            if (params.wethIsEth && address(token) == address(_weth)) {
                // Send WETH here and unwrap to native ETH.
                _vault.sendTo(_weth, address(this), amountOut);
                _weth.withdraw(amountOut);
                // Send ETH to sender.
                payable(params.sender).sendValue(amountOut);
            } else {
                // Transfer the token to the sender (amountOut).
                _vault.sendTo(token, params.sender, amountOut);
            }
        }

        _returnEth(params.sender);
    }

    /// @inheritdoc IRouterMain
    function removeLiquidityRecoveryHook(
        address pool,
        address sender,
        uint256 exactBptAmountIn
    ) external nonReentrant onlyVault returns (uint256[] memory amountsOut) {
        amountsOut = _vault.removeLiquidityRecovery(pool, sender, exactBptAmountIn);

        IERC20[] memory tokens = _vault.getPoolTokens(pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amountOut = amountsOut[i];
            if (amountOut > 0) {
                // Transfer the token to the sender (amountOut).
                _vault.sendTo(tokens[i], sender, amountOut);
            }
        }

        _returnEth(sender);
    }

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    /// @inheritdoc IRouterMain
    function swapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable saveSender(msg.sender) returns (uint256) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        Router.swapSingleTokenHook,
                        IRouterCommon.SwapSingleTokenHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_IN,
                            pool: pool,
                            tokenIn: tokenIn,
                            tokenOut: tokenOut,
                            amountGiven: exactAmountIn,
                            limit: minAmountOut,
                            deadline: deadline,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    /// @inheritdoc IRouterMain
    function swapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable saveSender(msg.sender) returns (uint256) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        Router.swapSingleTokenHook,
                        IRouterCommon.SwapSingleTokenHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_OUT,
                            pool: pool,
                            tokenIn: tokenIn,
                            tokenOut: tokenOut,
                            amountGiven: exactAmountOut,
                            limit: maxAmountIn,
                            deadline: deadline,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    /// @inheritdoc IRouterMain
    function swapSingleTokenHook(
        IRouterCommon.SwapSingleTokenHookParams calldata params
    ) external nonReentrant onlyVault returns (uint256) {
        (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) = _swapHook(params);

        IERC20 tokenIn = params.tokenIn;

        _takeTokenIn(params.sender, tokenIn, amountIn, params.wethIsEth);
        _sendTokenOut(params.sender, params.tokenOut, amountOut, params.wethIsEth);

        if (tokenIn == _weth) {
            // Return the rest of ETH to sender
            _returnEth(params.sender);
        }

        return amountCalculated;
    }

    /*******************************************************************************
                                  ERC4626 Buffers
    *******************************************************************************/

    /// @inheritdoc IRouterMain
    function initializeBuffer(
        IERC4626 wrappedToken,
        uint256 amountUnderlyingRaw,
        uint256 amountWrappedRaw
    ) external returns (uint256 issuedShares) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        Router.initializeBufferHook,
                        (
                            wrappedToken,
                            amountUnderlyingRaw,
                            amountWrappedRaw,
                            msg.sender // sharesOwner
                        )
                    )
                ),
                (uint256)
            );
    }

    /// @inheritdoc IRouterMain
    function initializeBufferHook(
        IERC4626 wrappedToken,
        uint256 amountUnderlyingRaw,
        uint256 amountWrappedRaw,
        address sharesOwner
    ) external nonReentrant onlyVault returns (uint256 issuedShares) {
        issuedShares = _vault.initializeBuffer(wrappedToken, amountUnderlyingRaw, amountWrappedRaw, sharesOwner);
        _takeTokenIn(sharesOwner, IERC20(wrappedToken.asset()), amountUnderlyingRaw, false);
        _takeTokenIn(sharesOwner, IERC20(address(wrappedToken)), amountWrappedRaw, false);
    }

    /// @inheritdoc IRouterMain
    function addLiquidityToBuffer(
        IERC4626 wrappedToken,
        uint256 exactSharesToIssue
    ) external returns (uint256 amountUnderlyingRaw, uint256 amountWrappedRaw) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        Router.addLiquidityToBufferHook,
                        (
                            wrappedToken,
                            exactSharesToIssue,
                            msg.sender // sharesOwner
                        )
                    )
                ),
                (uint256, uint256)
            );
    }

    /// @inheritdoc IRouterMain
    function addLiquidityToBufferHook(
        IERC4626 wrappedToken,
        uint256 exactSharesToIssue,
        address sharesOwner
    ) external nonReentrant onlyVault returns (uint256 amountUnderlyingRaw, uint256 amountWrappedRaw) {
        (amountUnderlyingRaw, amountWrappedRaw) = _vault.addLiquidityToBuffer(
            wrappedToken,
            exactSharesToIssue,
            sharesOwner
        );
        _takeTokenIn(sharesOwner, IERC20(wrappedToken.asset()), amountUnderlyingRaw, false);
        _takeTokenIn(sharesOwner, IERC20(address(wrappedToken)), amountWrappedRaw, false);
    }

    /*******************************************************************************
                                     Proxy handlers
    *******************************************************************************/

    /**
     * @inheritdoc Proxy
     * @dev Returns the RouterExtension contract, to which fallback requests are forwarded.
     */
    function _implementation() internal view override returns (address) {
        return address(_routerExtension);
    }

    /// @inheritdoc IRouterMain
    function getRouterExtension() external view returns (address) {
        return _implementation();
    }
}
