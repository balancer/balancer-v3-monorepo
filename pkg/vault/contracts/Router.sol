// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { Asset, AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ReentrancyGuard } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

contract Router is IRouter, ReentrancyGuard {
    using AssetHelpers for *;
    using Address for address payable;

    IVault private immutable _vault;

    // solhint-disable-next-line var-name-mixedcase
    IWETH private immutable _weth;

    modifier onlyVault() {
        if (msg.sender != address(_vault)) {
            revert IVault.SenderIsNotVault(msg.sender);
        }
        _;
    }

    constructor(IVault vault, address weth) {
        _vault = vault;
        _weth = IWETH(weth);
    }

    /*******************************************************************************
                                    Pools
    *******************************************************************************/

    /// @inheritdoc IRouter
    function initialize(
        address pool,
        Asset[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        return
            abi.decode(
                _vault.invoke{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.initializeCallback.selector,
                        InitializeCallbackParams({
                            sender: msg.sender,
                            pool: pool,
                            assets: assets,
                            maxAmountsIn: maxAmountsIn,
                            minBptAmountOut: minBptAmountOut,
                            userData: userData
                        })
                    )
                ),
                (uint256[], uint256)
            );
    }

    /**
     * @notice Callback for initialization.
     * @dev Can only be called by the Vault.
     * @param params Initialization parameters (see IRouter for struct definition)
     * @return amountsIn Actual amounts in required for the initial join
     * @return bptAmountOut BPT amount minted in exchange for the input tokens
     */
    function initializeCallback(
        InitializeCallbackParams calldata params
    ) external payable nonReentrant onlyVault returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        IERC20[] memory tokens = params.assets.toIERC20(_weth);

        (amountsIn, bptAmountOut) = _vault.initialize(
            params.pool,
            params.sender,
            tokens,
            params.maxAmountsIn,
            params.userData
        );

        if (bptAmountOut < params.minBptAmountOut) {
            revert BptAmountBelowMin();
        }

        uint256 ethAmountIn;
        for (uint256 i = 0; i < params.assets.length; ++i) {
            // Receive assets from the handler
            Asset asset = params.assets[i];
            uint256 amountIn = amountsIn[i];

            if (amountIn > params.maxAmountsIn[i]) {
                revert JoinAboveMax();
            }

            IERC20 token = asset.toIERC20(_weth);

            // There can be only one WETH token in the pool
            if (asset.isETH()) {
                _weth.deposit{ value: amountIn }();
                ethAmountIn = amountIn;
            }

            // transfer tokens from the user to the Vault
            _vault.retrieve(token, params.sender, amountIn);
        }

        // return ETH dust
        address(params.sender).returnEth(ethAmountIn);
    }

    /// @inheritdoc IRouter
    function addLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        IBasePool.AddLiquidityKind kind,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        return
            abi.decode(
                _vault.invoke{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.addLiquidityCallback.selector,
                        AddLiquidityCallbackParams({
                            sender: msg.sender,
                            pool: pool,
                            assets: assets,
                            maxAmountsIn: maxAmountsIn,
                            minBptAmountOut: minBptAmountOut,
                            kind: kind,
                            userData: userData
                        })
                    )
                ),
                (uint256[], uint256)
            );
    }

    /**
     * @notice Callback for adding liquidity.
     * @dev Can only be called by the Vault.
     * @param params Add liquiity parameters (see IRouter for struct definition)
     * @return amountsIn Actual amounts in required for the join
     * @return bptAmountOut BPT amount minted in exchange for the input tokens
     */
    function addLiquidityCallback(
        AddLiquidityCallbackParams calldata params
    ) external payable nonReentrant onlyVault returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        IERC20[] memory tokens = params.assets.toIERC20(_weth);

        (amountsIn, bptAmountOut) = _vault.addLiquidity(
            params.pool,
            params.sender,
            tokens,
            params.maxAmountsIn,
            params.minBptAmountOut,
            params.kind,
            params.userData
        );

        if (bptAmountOut < params.minBptAmountOut) {
            revert BptAmountBelowMin();
        }

        uint256 ethAmountIn;
        for (uint256 i = 0; i < params.assets.length; ++i) {
            // Receive assets from the handler
            Asset asset = params.assets[i];
            uint256 amountIn = amountsIn[i];

            if (amountIn > params.maxAmountsIn[i]) {
                revert JoinAboveMax();
            }

            IERC20 token = asset.toIERC20(_weth);

            // There can be only one WETH token in the pool
            if (asset.isETH()) {
                _weth.deposit{ value: amountIn }();
                ethAmountIn = amountIn;
            }
            _vault.retrieve(token, params.sender, amountIn);
        }

        // Send remaining ETH to the user
        address(params.sender).returnEth(ethAmountIn);
    }

    /// @inheritdoc IRouter
    function removeLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 maxBptAmountIn,
        IBasePool.RemoveLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        return
            abi.decode(
                _vault.invoke(
                    abi.encodeWithSelector(
                        Router.removeLiquidityCallback.selector,
                        RemoveLiquidityCallbackParams({
                            sender: msg.sender,
                            pool: pool,
                            assets: assets,
                            minAmountsOut: minAmountsOut,
                            maxBptAmountIn: maxBptAmountIn,
                            kind: kind,
                            userData: userData
                        })
                    )
                ),
                (uint256[], uint256)
            );
    }

    /**
     * @notice Callback for removing liquidity.
     * @dev Can only be called by the Vault.
     * @param params Remove liquiity parameters (see IRouter for struct definition)
     * @return amountsOut Actual token amounts transferred in exchange for the BPT
     * @return bptAmountIn BPT amount burned for the output tokens
     */
    function removeLiquidityCallback(
        RemoveLiquidityCallbackParams calldata params
    ) external nonReentrant onlyVault returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        IERC20[] memory tokens = params.assets.toIERC20(_weth);

        (amountsOut, bptAmountIn) = _vault.removeLiquidity(
            params.pool,
            params.sender,
            tokens,
            params.minAmountsOut,
            params.maxBptAmountIn,
            params.kind,
            params.userData
        );

        uint256 ethAmountOut;
        for (uint256 i = 0; i < params.assets.length; ++i) {
            uint256 amountOut = amountsOut[i];
            if (amountOut < params.minAmountsOut[i]) {
                revert ExitBelowMin();
            }

            Asset asset = params.assets[i];
            IERC20 token = asset.toIERC20(_weth);

            // Receive the asset amountOut
            _vault.wire(token, params.sender, amountOut);

            // There can be only one WETH token in the pool
            if (asset.isETH()) {
                // Withdraw WETH to ETH
                _weth.withdraw(amountOut);
                ethAmountOut = amountOut;
            }
        }

        // Send ETH to sender
        payable(params.sender).sendValue(ethAmountOut);
    }

    /// @inheritdoc IRouter
    function swap(
        IVault.SwapKind kind,
        address pool,
        Asset assetIn,
        Asset assetOut,
        uint256 amountGiven,
        uint256 limit,
        uint256 deadline,
        bytes calldata userData
    ) external payable returns (uint256) {
        return
            abi.decode(
                _vault.invoke{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.swapCallback.selector,
                        SwapCallbackParams({
                            sender: msg.sender,
                            kind: kind,
                            pool: pool,
                            assetIn: assetIn,
                            assetOut: assetOut,
                            amountGiven: amountGiven,
                            limit: limit,
                            deadline: deadline,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    /**
     * @notice Callback for swaps.
     * @dev Can only be called by the Vault. Also handles native ETH.
     * @param params Swap parameters (see IRouter for struct definition)
     * @return Token amount calculated by the pool math (e.g., amountOut for a given in swap)
     */
    function swapCallback(
        SwapCallbackParams calldata params
    ) external payable nonReentrant onlyVault returns (uint256) {
        (
            uint256 amountCalculated,
            uint256 amountIn,
            uint256 amountOut,
            IERC20 tokenIn,
            IERC20 tokenOut
        ) = _swapCallback(params);

        // If the assetIn is ETH, then wrap `amountIn` into WETH.
        if (params.assetIn.isETH()) {
            // wrap amountIn to WETH
            _weth.deposit{ value: amountIn }();
            // send WETH to Vault
            _weth.transfer(address(_vault), amountIn);
            // update Vault accounting
            _vault.settle(_weth);
        } else {
            // Send the assetIn amount to the Vault
            _vault.retrieve(tokenIn, params.sender, amountIn);
        }

        // If the assetOut is ETH, then unwrap `amountOut` into ETH.
        if (params.assetOut.isETH()) {
            // Receive the WETH amountOut
            _vault.wire(tokenOut, address(this), amountOut);
            // Withdraw WETH to ETH
            _weth.withdraw(amountOut);
            // Send ETH to sender
            payable(params.sender).sendValue(amountOut);
        } else {
            // Receive the tokenOut amountOut
            _vault.wire(tokenOut, params.sender, amountOut);
        }

        if (params.assetIn.isETH()) {
            // Return the rest of ETH to sender
            address(params.sender).returnEth(amountIn);
        }

        return amountCalculated;
    }

    function _swapCallback(
        SwapCallbackParams calldata params
    )
        internal
        returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut, IERC20 tokenIn, IERC20 tokenOut)
    {
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > params.deadline) {
            revert SwapDeadline();
        }

        tokenIn = params.assetIn.toIERC20(_weth);
        tokenOut = params.assetOut.toIERC20(_weth);

        (amountCalculated, amountIn, amountOut) = _vault.swap(
            IVault.SwapParams({
                kind: params.kind,
                pool: params.pool,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountGiven: params.amountGiven,
                userData: params.userData
            })
        );

        if (params.kind == IVault.SwapKind.GIVEN_IN ? amountOut < params.limit : amountIn > params.limit) {
            revert SwapLimit(params.kind == IVault.SwapKind.GIVEN_IN ? amountOut : amountIn, params.limit);
        }
    }

    /*******************************************************************************
                                    Queries
    *******************************************************************************/

    /// @inheritdoc IRouter
    function querySwap(
        IVault.SwapKind kind,
        address pool,
        Asset assetIn,
        Asset assetOut,
        uint256 amountGiven,
        bytes calldata userData
    ) external payable returns (uint256 amountCalculated) {
        return
            abi.decode(
                _vault.quote{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.querySwapCallback.selector,
                        SwapCallbackParams({
                            sender: msg.sender,
                            kind: kind,
                            pool: pool,
                            assetIn: assetIn,
                            assetOut: assetOut,
                            amountGiven: amountGiven,
                            limit: kind == IVault.SwapKind.GIVEN_IN ? 0 : type(uint256).max,
                            deadline: type(uint256).max,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    /**
     * @notice Callback for swap queries.
     * @dev Can only be called by the Vault. Also handles native ETH.
     * @param params Swap parameters (see IRouter for struct definition)
     * @return Token amount calculated by the pool math (e.g., amountOut for a given in swap)
     */
    function querySwapCallback(
        SwapCallbackParams calldata params
    ) external payable nonReentrant onlyVault returns (uint256) {
        (uint256 amountCalculated, , , , ) = _swapCallback(params);

        return amountCalculated;
    }

    /// @inheritdoc IRouter
    function queryAddLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        IBasePool.AddLiquidityKind kind,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        return
            abi.decode(
                _vault.quote{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.queryAddLiquidityCallback.selector,
                        AddLiquidityCallbackParams({
                            // we use router as a sender to simplify basic query functions
                            // but it is possible to add liquidity to any recepient
                            sender: address(this),
                            pool: pool,
                            assets: assets,
                            maxAmountsIn: maxAmountsIn,
                            minBptAmountOut: minBptAmountOut,
                            kind: kind,
                            userData: userData
                        })
                    )
                ),
                (uint256[], uint256)
            );
    }

    /**
     * @notice Callback for add liquidity queries.
     * @dev Can only be called by the Vault.
     * @param params Add liquiity parameters (see IRouter for struct definition)
     * @return amountsIn Actual amounts in required for the join
     * @return bptAmountOut BPT amount minted in exchange for the input tokens
     */
    function queryAddLiquidityCallback(
        AddLiquidityCallbackParams calldata params
    ) external payable nonReentrant onlyVault returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        IERC20[] memory tokens = params.assets.toIERC20(_weth);

        (amountsIn, bptAmountOut) = _vault.addLiquidity(
            params.pool,
            params.sender,
            tokens,
            params.maxAmountsIn,
            params.minBptAmountOut,
            params.kind,
            params.userData
        );
    }

    /// @inheritdoc IRouter
    function queryRemoveLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 maxBptAmountIn,
        IBasePool.RemoveLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeWithSelector(
                        Router.queryRemoveLiquidityCallback.selector,
                        RemoveLiquidityCallbackParams({
                            // We use router as a sender to simplify basic query functions
                            // but it is possible to remove liquidity from any sender
                            sender: address(this),
                            pool: pool,
                            assets: assets,
                            minAmountsOut: minAmountsOut,
                            maxBptAmountIn: maxBptAmountIn,
                            kind: kind,
                            userData: userData
                        })
                    )
                ),
                (uint256[], uint256)
            );
    }

    /**
     * @notice Callback for remove liquidity queries.
     * @dev Can only be called by the Vault.
     * @param params Remove liquiity parameters (see IRouter for struct definition)
     * @return amountsOut Actual token amounts transferred in exchange for the BPT
     * @return bptAmountIn BPT amount burned for the output tokens
     */
    function queryRemoveLiquidityCallback(
        RemoveLiquidityCallbackParams calldata params
    ) external nonReentrant onlyVault returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        return
            _vault.removeLiquidity(
                params.pool,
                params.sender,
                params.assets.toIERC20(_weth),
                params.minAmountsOut,
                params.maxBptAmountIn,
                params.kind,
                params.userData
            );
    }
}
