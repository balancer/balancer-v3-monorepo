// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { RouterCommon } from "./RouterCommon.sol";

contract Router is IRouter, RouterCommon, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using Address for address payable;

    constructor(IVault vault, IWETH weth, IPermit2 permit2) RouterCommon(vault, weth, permit2) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /*******************************************************************************
                                    Pools
    *******************************************************************************/

    /// @inheritdoc IRouter
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
                _vault.unlock{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.initializeHook.selector,
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

    /**
     * @notice Hook for initialization.
     * @dev Can only be called by the Vault.
     * @param params Initialization parameters (see IRouter for struct definition)
     * @return bptAmountOut BPT amount minted in exchange for the input tokens
     */
    function initializeHook(
        InitializeHookParams calldata params
    ) external payable nonReentrant onlyVault returns (uint256 bptAmountOut) {
        bptAmountOut = _vault.initialize(
            params.pool,
            params.sender,
            params.tokens,
            params.exactAmountsIn,
            params.minBptAmountOut,
            params.userData
        );

        uint256 ethAmountIn;
        for (uint256 i = 0; i < params.tokens.length; ++i) {
            IERC20 token = params.tokens[i];
            uint256 amountIn = params.exactAmountsIn[i];

            // There can be only one WETH token in the pool
            if (params.wethIsEth && address(token) == address(_weth)) {
                if (msg.value < amountIn) {
                    revert InsufficientEth();
                }
                _weth.deposit{ value: amountIn }();
                ethAmountIn = amountIn;
                // transfer WETH from the router to the Vault
                _weth.transfer(address(_vault), amountIn);
                _vault.settle(_weth);
            } else {
                // transfer tokens from the user to the Vault
                _permit2.transferFrom(params.sender, address(_vault), uint160(amountIn), address(token));
                _vault.settle(token);
            }
        }

        // return ETH dust
        _returnEth(params.sender, ethAmountIn);
    }

    /// @inheritdoc IRouter
    function addLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn) {
        (amountsIn, , ) = abi.decode(
            _vault.unlock{ value: msg.value }(
                abi.encodeWithSelector(
                    Router.addLiquidityHook.selector,
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

    /// @inheritdoc IRouter
    function addLiquidityUnbalanced(
        address pool,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut) {
        (, bptAmountOut, ) = abi.decode(
            _vault.unlock{ value: msg.value }(
                abi.encodeWithSelector(
                    Router.addLiquidityHook.selector,
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

    /// @inheritdoc IRouter
    function addLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        uint256 maxAmountIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 amountIn) {
        (uint256[] memory maxAmountsIn, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
            pool,
            tokenIn,
            maxAmountIn
        );

        (uint256[] memory amountsIn, , ) = abi.decode(
            _vault.unlock{ value: msg.value }(
                abi.encodeWithSelector(
                    Router.addLiquidityHook.selector,
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

    /// @inheritdoc IRouter
    function addLiquidityCustom(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        return
            abi.decode(
                _vault.unlock{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.addLiquidityHook.selector,
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

    /**
     * @notice Hook for adding liquidity.
     * @dev Can only be called by the Vault.
     * @param params Add liquidity parameters (see IRouter for struct definition)
     * @return amountsIn Actual amounts in required for the join
     * @return bptAmountOut BPT amount minted in exchange for the input tokens
     */
    function addLiquidityHook(
        AddLiquidityHookParams calldata params
    )
        external
        payable
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

        // maxAmountsIn length is checked against tokens length at the vault.
        IERC20[] memory tokens = _vault.getPoolTokens(params.pool);

        uint256 ethAmountIn;
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 amountIn = amountsIn[i];

            // There can be only one WETH token in the pool
            if (params.wethIsEth && address(token) == address(_weth)) {
                if (msg.value < amountIn) {
                    revert InsufficientEth();
                }

                _weth.deposit{ value: amountIn }();
                ethAmountIn = amountIn;
                _weth.transfer(address(_vault), amountIn);
                _vault.settle(_weth);
            } else {
                _permit2.transferFrom(params.sender, address(_vault), uint160(amountIn), address(token));
                _vault.settle(token);
            }
        }

        // Send remaining ETH to the user
        _returnEth(params.sender, ethAmountIn);
    }

    /// @inheritdoc IRouter
    function removeLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsOut) {
        (, amountsOut, ) = abi.decode(
            _vault.unlock(
                abi.encodeWithSelector(
                    Router.removeLiquidityHook.selector,
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

    /// @inheritdoc IRouter
    function removeLiquiditySingleTokenExactIn(
        address pool,
        uint256 exactBptAmountIn,
        IERC20 tokenOut,
        uint256 minAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 amountOut) {
        (uint256[] memory minAmountsOut, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
            pool,
            tokenOut,
            minAmountOut
        );

        (, uint256[] memory amountsOut, ) = abi.decode(
            _vault.unlock(
                abi.encodeWithSelector(
                    Router.removeLiquidityHook.selector,
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

    /// @inheritdoc IRouter
    function removeLiquiditySingleTokenExactOut(
        address pool,
        uint256 maxBptAmountIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountIn) {
        (uint256[] memory minAmountsOut, ) = _getSingleInputArrayAndTokenIndex(pool, tokenOut, exactAmountOut);

        (bptAmountIn, , ) = abi.decode(
            _vault.unlock(
                abi.encodeWithSelector(
                    Router.removeLiquidityHook.selector,
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

    /// @inheritdoc IRouter
    function removeLiquidityCustom(
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeWithSelector(
                        Router.removeLiquidityHook.selector,
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

    /// @inheritdoc IRouter
    function removeLiquidityRecovery(
        address pool,
        uint256 exactBptAmountIn
    ) external returns (uint256[] memory amountsOut) {
        amountsOut = abi.decode(
            _vault.unlock(
                abi.encodeWithSelector(Router.removeLiquidityRecoveryHook.selector, pool, msg.sender, exactBptAmountIn)
            ),
            (uint256[])
        );
    }

    /**
     * @notice Hook for removing liquidity.
     * @dev Can only be called by the Vault.
     * @param params Remove liquidity parameters (see IRouter for struct definition)
     * @return bptAmountIn BPT amount burned for the output tokens
     * @return amountsOut Actual token amounts transferred in exchange for the BPT
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
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

        // minAmountsOut length is checked against tokens length at the vault.
        IERC20[] memory tokens = _vault.getPoolTokens(params.pool);

        uint256 ethAmountOut;
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amountOut = amountsOut[i];
            IERC20 token = tokens[i];

            if (amountOut < params.minAmountsOut[i]) {
                revert ExitBelowMin(amountOut, params.minAmountsOut[i]);
            }

            // There can be only one WETH token in the pool
            if (params.wethIsEth && address(token) == address(_weth)) {
                // Send WETH here and unwrap to native ETH
                _vault.sendTo(_weth, address(this), amountOut);
                _weth.withdraw(amountOut);
                ethAmountOut = amountOut;
            } else {
                // Transfer the token to the sender (amountOut)
                _vault.sendTo(token, params.sender, amountOut);
            }
        }

        // Send ETH to sender
        payable(params.sender).sendValue(ethAmountOut);
    }

    /**
     * @notice Hook for removing liquidity in Recovery Mode.
     * @dev Can only be called by the Vault, when the pool is in Recovery Mode.
     * @param pool Address of the liquidity pool
     * @param sender Account originating the remove liquidity operation
     * @param exactBptAmountIn BPT amount burned for the output tokens
     * @return amountsOut Actual token amounts transferred in exchange for the BPT
     */
    function removeLiquidityRecoveryHook(
        address pool,
        address sender,
        uint256 exactBptAmountIn
    ) external nonReentrant onlyVault returns (uint256[] memory amountsOut) {
        amountsOut = _vault.removeLiquidityRecovery(pool, sender, exactBptAmountIn);

        IERC20[] memory tokens = _vault.getPoolTokens(pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            // Transfer the token to the sender (amountOut)
            _vault.sendTo(tokens[i], sender, amountsOut[i]);
        }
    }

    /// @inheritdoc IRouter
    function swapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256) {
        return
            abi.decode(
                _vault.unlock{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.swapSingleTokenHook.selector,
                        SwapSingleTokenHookParams({
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

    /// @inheritdoc IRouter
    function swapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256) {
        return
            abi.decode(
                _vault.unlock{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.swapSingleTokenHook.selector,
                        SwapSingleTokenHookParams({
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

    /**
     * @notice Hook for swaps.
     * @dev Can only be called by the Vault. Also handles native ETH.
     * @param params Swap parameters (see IRouter for struct definition)
     * @return Token amount calculated by the pool math (e.g., amountOut for a exact in swap)
     */
    function swapSingleTokenHook(
        SwapSingleTokenHookParams calldata params
    ) external payable nonReentrant onlyVault returns (uint256) {
        (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) = _swapHook(params);

        IERC20 tokenIn = params.tokenIn;
        bool wethIsEth = params.wethIsEth;

        uint256 ethAmountIn = _takeTokenIn(params.sender, tokenIn, amountIn, wethIsEth);
        _sendTokenOut(params.sender, params.tokenOut, amountOut, wethIsEth);

        if (tokenIn == _weth) {
            // Return the rest of ETH to sender
            _returnEth(params.sender, ethAmountIn);
        }

        return amountCalculated;
    }

    function _swapHook(
        SwapSingleTokenHookParams calldata params
    ) internal returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) {
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > params.deadline) {
            revert SwapDeadline();
        }

        (amountCalculated, amountIn, amountOut) = _vault.swap(
            SwapParams({
                kind: params.kind,
                pool: params.pool,
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                amountGivenRaw: params.amountGiven,
                limitRaw: params.limit,
                userData: params.userData
            })
        );
    }

    /*******************************************************************************
                                    Queries
    *******************************************************************************/

    /// @inheritdoc IRouter
    function querySwapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        bytes calldata userData
    ) external returns (uint256 amountCalculated) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeWithSelector(
                        Router.querySwapHook.selector,
                        SwapSingleTokenHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_IN,
                            pool: pool,
                            tokenIn: tokenIn,
                            tokenOut: tokenOut,
                            amountGiven: exactAmountIn,
                            limit: 0,
                            deadline: _MAX_AMOUNT,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    /// @inheritdoc IRouter
    function querySwapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        bytes calldata userData
    ) external returns (uint256 amountCalculated) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeWithSelector(
                        Router.querySwapHook.selector,
                        SwapSingleTokenHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_OUT,
                            pool: pool,
                            tokenIn: tokenIn,
                            tokenOut: tokenOut,
                            amountGiven: exactAmountOut,
                            limit: _MAX_AMOUNT,
                            deadline: type(uint256).max,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    /**
     * @notice Hook for swap queries.
     * @dev Can only be called by the Vault. Also handles native ETH.
     * @param params Swap parameters (see IRouter for struct definition)
     * @return Token amount calculated by the pool math (e.g., amountOut for a exact in swap)
     */
    function querySwapHook(
        SwapSingleTokenHookParams calldata params
    ) external payable nonReentrant onlyVault returns (uint256) {
        (uint256 amountCalculated, , ) = _swapHook(params);

        return amountCalculated;
    }

    /// @inheritdoc IRouter
    function queryAddLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn) {
        (amountsIn, , ) = abi.decode(
            _vault.quote(
                abi.encodeWithSelector(
                    Router.queryAddLiquidityHook.selector,
                    AddLiquidityHookParams({
                        // we use router as a sender to simplify basic query functions
                        // but it is possible to add liquidity to any recipient
                        sender: address(this),
                        pool: pool,
                        maxAmountsIn: maxAmountsIn,
                        minBptAmountOut: exactBptAmountOut,
                        kind: AddLiquidityKind.UNBALANCED,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256[], uint256, bytes)
        );
    }

    /// @inheritdoc IRouter
    function queryAddLiquidityUnbalanced(
        address pool,
        uint256[] memory exactAmountsIn,
        bytes memory userData
    ) external returns (uint256 bptAmountOut) {
        (, bptAmountOut, ) = abi.decode(
            _vault.quote(
                abi.encodeWithSelector(
                    Router.queryAddLiquidityHook.selector,
                    AddLiquidityHookParams({
                        // we use router as a sender to simplify basic query functions
                        // but it is possible to add liquidity to any recipient
                        sender: address(this),
                        pool: pool,
                        maxAmountsIn: exactAmountsIn,
                        minBptAmountOut: 0,
                        kind: AddLiquidityKind.UNBALANCED,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256[], uint256, bytes)
        );
    }

    /// @inheritdoc IRouter
    function queryAddLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) external returns (uint256 amountIn) {
        (uint256[] memory maxAmountsIn, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
            pool,
            tokenIn,
            _MAX_AMOUNT
        );

        (uint256[] memory amountsIn, , ) = abi.decode(
            _vault.quote(
                abi.encodeWithSelector(
                    Router.queryAddLiquidityHook.selector,
                    AddLiquidityHookParams({
                        // we use router as a sender to simplify basic query functions
                        // but it is possible to add liquidity to any recipient
                        sender: address(this),
                        pool: pool,
                        maxAmountsIn: maxAmountsIn,
                        minBptAmountOut: exactBptAmountOut,
                        kind: AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256[], uint256, bytes)
        );

        return amountsIn[tokenIndex];
    }

    /// @inheritdoc IRouter
    function queryAddLiquidityCustom(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeWithSelector(
                        Router.queryAddLiquidityHook.selector,
                        AddLiquidityHookParams({
                            // we use router as a sender to simplify basic query functions
                            // but it is possible to add liquidity to any recipient
                            sender: address(this),
                            pool: pool,
                            maxAmountsIn: maxAmountsIn,
                            minBptAmountOut: minBptAmountOut,
                            kind: AddLiquidityKind.CUSTOM,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256[], uint256, bytes)
            );
    }

    /**
     * @notice Hook for add liquidity queries.
     * @dev Can only be called by the Vault.
     * @param params Add liquidity parameters (see IRouter for struct definition)
     * @return amountsIn Actual token amounts in required as inputs
     * @return bptAmountOut Expected pool tokens to be minted
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function queryAddLiquidityHook(
        AddLiquidityHookParams calldata params
    )
        external
        payable
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
    }

    /// @inheritdoc IRouter
    function queryRemoveLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut) {
        uint256[] memory minAmountsOut = new uint256[](_vault.getPoolTokens(pool).length);
        (, amountsOut, ) = abi.decode(
            _vault.quote(
                abi.encodeWithSelector(
                    Router.queryRemoveLiquidityHook.selector,
                    RemoveLiquidityHookParams({
                        // We use router as a sender to simplify basic query functions
                        // but it is possible to remove liquidity from any sender
                        sender: address(this),
                        pool: pool,
                        minAmountsOut: minAmountsOut,
                        maxBptAmountIn: exactBptAmountIn,
                        kind: RemoveLiquidityKind.PROPORTIONAL,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256, uint256[], bytes)
        );
    }

    /// @inheritdoc IRouter
    function queryRemoveLiquiditySingleTokenExactIn(
        address pool,
        uint256 exactBptAmountIn,
        IERC20 tokenOut,
        bytes memory userData
    ) external returns (uint256 amountOut) {
        // We cannot use 0 as min amount out, as the value is used to figure out the token index.
        (uint256[] memory minAmountsOut, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(pool, tokenOut, 1);

        (, uint256[] memory amountsOut, ) = abi.decode(
            _vault.quote(
                abi.encodeWithSelector(
                    Router.queryRemoveLiquidityHook.selector,
                    RemoveLiquidityHookParams({
                        // We use router as a sender to simplify basic query functions
                        // but it is possible to remove liquidity from any sender
                        sender: address(this),
                        pool: pool,
                        minAmountsOut: minAmountsOut,
                        maxBptAmountIn: exactBptAmountIn,
                        kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256, uint256[], bytes)
        );

        return amountsOut[tokenIndex];
    }

    /// @inheritdoc IRouter
    function queryRemoveLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        bytes memory userData
    ) external returns (uint256 bptAmountIn) {
        (uint256[] memory minAmountsOut, ) = _getSingleInputArrayAndTokenIndex(pool, tokenOut, exactAmountOut);

        (bptAmountIn, , ) = abi.decode(
            _vault.quote(
                abi.encodeWithSelector(
                    Router.queryRemoveLiquidityHook.selector,
                    RemoveLiquidityHookParams({
                        // We use router as a sender to simplify basic query functions
                        // but it is possible to remove liquidity from any sender
                        sender: address(this),
                        pool: pool,
                        minAmountsOut: minAmountsOut,
                        maxBptAmountIn: _MAX_AMOUNT,
                        kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                        wethIsEth: false,
                        userData: userData
                    })
                )
            ),
            (uint256, uint256[], bytes)
        );

        return bptAmountIn;
    }

    /// @inheritdoc IRouter
    function queryRemoveLiquidityCustom(
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) external returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeWithSelector(
                        Router.queryRemoveLiquidityHook.selector,
                        RemoveLiquidityHookParams({
                            // We use router as a sender to simplify basic query functions
                            // but it is possible to remove liquidity from any sender
                            sender: address(this),
                            pool: pool,
                            minAmountsOut: minAmountsOut,
                            maxBptAmountIn: maxBptAmountIn,
                            kind: RemoveLiquidityKind.CUSTOM,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256, uint256[], bytes)
            );
    }

    /// @inheritdoc IRouter
    function queryRemoveLiquidityRecovery(
        address pool,
        uint256 exactBptAmountIn
    ) external returns (uint256[] memory amountsOut) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeWithSelector(
                        Router.queryRemoveLiquidityRecoveryHook.selector,
                        pool,
                        address(this),
                        exactBptAmountIn
                    )
                ),
                (uint256[])
            );
    }

    /**
     * @notice Hook for remove liquidity queries.
     * @dev Can only be called by the Vault.
     * @param params Remove liquidity parameters (see IRouter for struct definition)
     * @return bptAmountIn Pool token amount to be burned for the output tokens
     * @return amountsOut Expected token amounts to be transferred to the sender
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function queryRemoveLiquidityHook(
        RemoveLiquidityHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData)
    {
        // If router is the sender, it has to approve itself.
        IERC20(params.pool).approve(address(this), type(uint256).max);
        return
            _vault.removeLiquidity(
                RemoveLiquidityParams({
                    pool: params.pool,
                    from: params.sender,
                    maxBptAmountIn: params.maxBptAmountIn,
                    minAmountsOut: params.minAmountsOut,
                    kind: params.kind,
                    userData: params.userData
                })
            );
    }

    /**
     * @notice Hook for remove liquidity queries.
     * @dev Can only be called by the Vault.
     * @param pool The liquidity pool
     * @param sender Account originating the remove liquidity operation
     * @param exactBptAmountIn Pool token amount to be burned for the output tokens
     * @return amountsOut Expected token amounts to be transferred to the sender
     */
    function queryRemoveLiquidityRecoveryHook(
        address pool,
        address sender,
        uint256 exactBptAmountIn
    ) external nonReentrant onlyVault returns (uint256[] memory amountsOut) {
        return _vault.removeLiquidityRecovery(pool, sender, exactBptAmountIn);
    }

    /*******************************************************************************
                                    Utils
    *******************************************************************************/

    /// @inheritdoc IRouter
    function permitBatchAndCall(
        PermitApproval[] calldata permitBatch,
        bytes[] calldata permitSignatures,
        IAllowanceTransfer.PermitBatch calldata permit2Batch,
        bytes calldata permit2Signature,
        bytes[] calldata multicallData
    ) external virtual returns (bytes[] memory results) {
        // Use Permit (ERC-2612) to grant allowances to Permit2 for swapable tokens,
        // and grant allowances to Vault for BPT tokens.
        for (uint256 i = 0; i < permitBatch.length; ++i) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            bytes memory signature = permitSignatures[i];
            /// @solidity memory-safe-assembly
            // solhint-disable-next-line no-inline-assembly
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
            IRouter.PermitApproval memory permitApproval = permitBatch[i];
            IERC20Permit(permitApproval.token).permit(
                permitApproval.owner,
                address(this),
                permitApproval.amount,
                permitApproval.deadline,
                v,
                r,
                s
            );
        }
        // Use Permit2 for tokens that are swapped and added into the Vault.
        _permit2.permit(msg.sender, permit2Batch, permit2Signature);
        // Execute all the required operations once permissions have been granted.
        return multicall(multicallData);
    }

    /// @inheritdoc IRouter
    function multicall(bytes[] calldata data) public virtual returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; ++i) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
        return results;
    }
}
