// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import { Asset, AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";

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
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut) {
        return
            abi.decode(
                _vault.invoke{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.initializeCallback.selector,
                        InitializeCallbackParams({
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
     * @notice Callback for initialization.
     * @dev Can only be called by the Vault.
     * @param params Initialization parameters (see IRouter for struct definition)
     * @return bptAmountOut BPT amount minted in exchange for the input tokens
     */
    function initializeCallback(
        InitializeCallbackParams calldata params
    ) external payable nonReentrant onlyVault returns (uint256 bptAmountOut) {
        bptAmountOut = _vault.initialize(params.pool, params.sender, params.tokens, params.exactAmountsIn, params.userData);

        if (bptAmountOut < params.minBptAmountOut) {
            revert BptAmountBelowMin();
        }

        uint256 ethAmountIn;
        for (uint256 i = 0; i < params.tokens.length; ++i) {
            // Receive tokens from the handler
            IERC20 token = params.tokens[i];
            uint256 amountIn = params.exactAmountsIn[i];

            // There can be only one WETH token in the pool
            if (params.wethIsEth && address(token) == address(_weth)) {
                _weth.deposit{ value: amountIn }();
                ethAmountIn = amountIn;
            }
            // transfer tokens from the user to the Vault
            _vault.retrieve(token, params.sender, amountIn);
        }

        // return ETH dust
        address(params.sender).returnEth(msg.value - ethAmountIn);
    }

    /// @inheritdoc IRouter
    function addLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn) {
        (amountsIn, , ) = 
            abi.decode(
                _vault.invoke{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.addLiquidityCallback.selector,
                        AddLiquidityCallbackParams({
                            sender: msg.sender,
                            pool: pool,
                            maxAmountsIn: maxAmountsIn,
                            minBptAmountOut: exactBptAmountOut,
                            kind: IVault.AddLiquidityKind.PROPORTIONAL,
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
        (, bptAmountOut, ) = 
            abi.decode(
                _vault.invoke{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.addLiquidityCallback.selector,
                        AddLiquidityCallbackParams({
                            sender: msg.sender,
                            pool: pool,
                            maxAmountsIn: exactAmountsIn,
                            minBptAmountOut: minBptAmountOut,
                            kind: IVault.AddLiquidityKind.UNBALANCED,
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
        uint256 tokenInIndex,
        uint256 maxAmountIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 amountIn) {
        IERC20[] memory tokens = _vault.getPoolTokens(pool);

        if (tokenInIndex >= tokens.length) {
            revert InvalidTokenIndex();
        }

        uint256[] memory maxAmountsIn = new uint256[](tokens.length);
        maxAmountsIn[tokenInIndex] = maxAmountIn;

        (uint256[] memory amountsIn, , ) = 
            abi.decode(
                _vault.invoke{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.addLiquidityCallback.selector,
                        AddLiquidityCallbackParams({
                            sender: msg.sender,
                            pool: pool,
                            maxAmountsIn: maxAmountsIn,
                            minBptAmountOut: exactBptAmountOut,
                            kind: IVault.AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256[], uint256, bytes)
            );

        return amountsIn[tokenInIndex];
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
                _vault.invoke{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.addLiquidityCallback.selector,
                        AddLiquidityCallbackParams({
                            sender: msg.sender,
                            pool: pool,
                            maxAmountsIn: maxAmountsIn,
                            minBptAmountOut: minBptAmountOut,
                            kind: IVault.AddLiquidityKind.CUSTOM,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256[], uint256, bytes)
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
    )
        external
        payable
        nonReentrant
        onlyVault
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData)
    {
        (amountsIn, bptAmountOut, returnData) = _vault.addLiquidity(
            params.pool,
            params.sender,
            params.maxAmountsIn,
            params.minBptAmountOut,
            params.kind,
            params.userData
        );

        // maxAmountsIn length is checked against tokens length at the vault.
        IERC20[] memory tokens = _vault.getPoolTokens(params.pool);

        if (bptAmountOut < params.minBptAmountOut) {
            revert BptAmountBelowMin();
        }

        uint256 ethAmountIn;
        for (uint256 i = 0; i < tokens.length; ++i) {
            // Receive tokens from the handler
            IERC20 token = tokens[i];
            uint256 amountIn = amountsIn[i];

            // TODO: check amounts in for every type.
            if (amountIn > params.maxAmountsIn[i]) {
                revert JoinAboveMax();
            }

            // There can be only one WETH token in the pool
            if (params.wethIsEth && address(token) == address(_weth)) {
                _weth.deposit{ value: amountIn }();
                ethAmountIn = amountIn;
            }
            _vault.retrieve(token, params.sender, amountIn);
        }

        // Send remaining ETH to the user
        address(params.sender).returnEth(ethAmountIn);
    }

    /// @inheritdoc IRouter
    function removeLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsOut) {
        (, amountsOut,) =
            abi.decode(
                _vault.invoke(
                    abi.encodeWithSelector(
                        Router.removeLiquidityCallback.selector,
                        RemoveLiquidityCallbackParams({
                            sender: msg.sender,
                            pool: pool,
                            minAmountsOut: minAmountsOut,
                            maxBptAmountIn: exactBptAmountIn,
                            kind: IVault.RemoveLiquidityKind.PROPORTIONAL,
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
        uint256 tokenOutIndex,
        uint256 minAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsOut) {
        IERC20[] memory tokens = _vault.getPoolTokens(pool);
        uint256 numTokens = tokens.length;

        if (tokenOutIndex >= numTokens) {
            revert InvalidTokenIndex();
        }

        uint256[] memory minAmountsOut = new uint256[](numTokens);
        minAmountsOut[tokenOutIndex] = minAmountOut;

        (, amountsOut,) =
            abi.decode(
                _vault.invoke(
                    abi.encodeWithSelector(
                        Router.removeLiquidityCallback.selector,
                        RemoveLiquidityCallbackParams({
                            sender: msg.sender,
                            pool: pool,
                            minAmountsOut: minAmountsOut,
                            maxBptAmountIn: exactBptAmountIn,
                            kind: IVault.RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256, uint256[], bytes)
            );

        return amountsOut;
    }

    /// @inheritdoc IRouter
    function removeLiquiditySingleTokenExactOut(
        address pool,
        uint256 maxBptAmountIn,
        uint256 tokenOutIndex,
        uint256 exactAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountIn) {
        IERC20[] memory tokens = _vault.getPoolTokens(pool);
        uint256 numTokens = tokens.length;

        if (tokenOutIndex >= numTokens) {
            revert InvalidTokenIndex();
        }

        uint256[] memory minAmountsOut = new uint256[](numTokens);
        minAmountsOut[tokenOutIndex] = exactAmountOut;

        (bptAmountIn, ,) =
            abi.decode(
                _vault.invoke(
                    abi.encodeWithSelector(
                        Router.removeLiquidityCallback.selector,
                        RemoveLiquidityCallbackParams({
                            sender: msg.sender,
                            pool: pool,
                            minAmountsOut: minAmountsOut,
                            maxBptAmountIn: maxBptAmountIn,
                            kind: IVault.RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
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
                _vault.invoke(
                    abi.encodeWithSelector(
                        Router.removeLiquidityCallback.selector,
                        RemoveLiquidityCallbackParams({
                            sender: msg.sender,
                            pool: pool,
                            minAmountsOut: minAmountsOut,
                            maxBptAmountIn: maxBptAmountIn,
                            kind: IVault.RemoveLiquidityKind.CUSTOM,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256, uint256[], bytes)
            );
    }

    /**
     * @notice Callback for removing liquidity.
     * @dev Can only be called by the Vault.
     * @param params Remove liquiity parameters (see IRouter for struct definition)
     * @return bptAmountIn BPT amount burned for the output tokens
     * @return amountsOut Actual token amounts transferred in exchange for the BPT
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function removeLiquidityCallback(
        RemoveLiquidityCallbackParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData)
    {
        (bptAmountIn, amountsOut, returnData) = _vault.removeLiquidity(
            params.pool,
            params.sender,
            params.maxBptAmountIn,
            params.minAmountsOut,
            params.kind,
            params.userData
        );

        // minAmountsOut length is checked against tokens length at the vault.
        IERC20[] memory tokens = _vault.getPoolTokens(params.pool);

        uint256 ethAmountOut;
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amountOut = amountsOut[i];
            IERC20 token = tokens[i];

            if (amountOut < params.minAmountsOut[i]) {
                revert ExitBelowMin();
            }

            // Receive the token amountOut
            _vault.wire(token, params.sender, amountOut);

            // There can be only one WETH token in the pool
            if (params.wethIsEth && address(token) == address(_weth)) {
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
                amountGivenRaw: params.amountGiven,
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
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        IVault.AddLiquidityKind kind,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
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
                            maxAmountsIn: maxAmountsIn,
                            minBptAmountOut: minBptAmountOut,
                            kind: kind,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256[], uint256, bytes)
            );
    }

    /**
     * @notice Callback for add liquidity queries.
     * @dev Can only be called by the Vault.
     * @param params Add liquiity parameters (see IRouter for struct definition)
     * @return amountsIn Actual token amounts in required as inputs
     * @return bptAmountOut Expected pool tokens to be minted
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function queryAddLiquidityCallback(
        AddLiquidityCallbackParams calldata params
    )
        external
        payable
        nonReentrant
        onlyVault
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData)
    {
        (amountsIn, bptAmountOut, returnData) = _vault.addLiquidity(
            params.pool,
            params.sender,
            params.maxAmountsIn,
            params.minBptAmountOut,
            params.kind,
            params.userData
        );
    }

    /// @inheritdoc IRouter
    function queryRemoveLiquidity(
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        IVault.RemoveLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData) {
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
                            minAmountsOut: minAmountsOut,
                            maxBptAmountIn: maxBptAmountIn,
                            kind: kind,
                            wethIsEth: false,
                            userData: userData
                        })
                    )
                ),
                (uint256, uint256[], bytes)
            );
    }

    /**
     * @notice Callback for remove liquidity queries.
     * @dev Can only be called by the Vault.
     * @param params Remove liquiity parameters (see IRouter for struct definition)
     * @return bptAmountIn Pool token amount to be burned for the output tokens
     * @return amountsOut Expected token amounts to be transferred to the sender
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function queryRemoveLiquidityCallback(
        RemoveLiquidityCallbackParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData)
    {
        return
            _vault.removeLiquidity(
                params.pool,
                params.sender,
                params.maxBptAmountIn,
                params.minAmountsOut,
                params.kind,
                params.userData
            );
    }
}
