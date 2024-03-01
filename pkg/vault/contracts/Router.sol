// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";

contract Router is IRouter, ReentrancyGuard {
    using Address for address payable;
    using EnumerableSet for EnumerableSet.AddressSet;

    IVault private immutable _vault;

    // solhint-disable-next-line var-name-mixedcase
    IWETH private immutable _weth;

    // Transient storage used to track tokens and amount flowing in and out within a batch swap.
    // Set of input tokens involved in a batch swap.
    EnumerableSet.AddressSet private _currentSwapTokensIn;
    // Set of output tokens involved in a batch swap.
    EnumerableSet.AddressSet private _currentSwapTokensOut;
    // token in -> amount: tracks token in amounts within a batch swap.
    mapping(address => uint256) private _currentSwapTokenInAmounts;
    // token out -> amount: tracks token out amounts within a batch swap.
    mapping(address => uint256) private _currentSwapTokenOutAmounts;
    // token -> amount that is part of the current input / output amounts, but is settled preemptively.
    mapping(address => uint256) private _settledTokenAmounts;

    modifier onlyVault() {
        _ensureOnlyVault();
        _;
    }

    function _ensureOnlyVault() private view {
        if (msg.sender != address(_vault)) {
            revert IVaultErrors.SenderIsNotVault(msg.sender);
        }
    }

    constructor(IVault vault, IWETH weth) {
        _vault = vault;
        _weth = weth;
        weth.approve(address(_vault), type(uint256).max);
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
                _vault.lock{ value: msg.value }(
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
            // Receive tokens from the locker
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
                _vault.takeFrom(_weth, address(this), amountIn);
            } else {
                // transfer tokens from the user to the Vault
                _vault.takeFrom(token, params.sender, amountIn);
            }
        }

        // return ETH dust
        _returnEth(params.sender, ethAmountIn);
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
            _vault.lock{ value: msg.value }(
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
            _vault.lock{ value: msg.value }(
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
                _vault.lock{ value: msg.value }(
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
            // Receive tokens from the locker
            IERC20 token = tokens[i];
            uint256 amountIn = amountsIn[i];

            // There can be only one WETH token in the pool
            if (params.wethIsEth && address(token) == address(_weth)) {
                if (msg.value < amountIn) {
                    revert InsufficientEth();
                }

                _weth.deposit{ value: amountIn }();
                ethAmountIn = amountIn;
                _vault.takeFrom(_weth, address(this), amountIn);
            } else {
                _vault.takeFrom(token, params.sender, amountIn);
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
            _vault.lock(
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
            _vault.lock(
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
            _vault.lock(
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
                _vault.lock(
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
            _vault.lock(
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
                _vault.lock{ value: msg.value }(
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
                _vault.lock{ value: msg.value }(
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

    /// @inheritdoc IRouter
    function swapExactIn(
        SwapPathExactAmountIn[] memory paths,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    )
        external
        payable
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        return
            abi.decode(
                _vault.lock{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.swapExactInHook.selector,
                        SwapExactInHookParams({
                            sender: msg.sender,
                            paths: paths,
                            deadline: deadline,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256[], address[], uint256[])
            );
    }

    /// @inheritdoc IRouter
    function swapExactOut(
        SwapPathExactAmountOut[] memory paths,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) {
        return
            abi.decode(
                _vault.lock{ value: msg.value }(
                    abi.encodeWithSelector(
                        Router.swapExactOutHook.selector,
                        SwapExactOutHookParams({
                            sender: msg.sender,
                            paths: paths,
                            deadline: deadline,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256[], address[], uint256[])
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

    function swapExactInHook(
        SwapExactInHookParams calldata params
    )
        external
        payable
        nonReentrant
        onlyVault
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        pathAmountsOut = _swapExactInHook(params);

        // The hook writes current swap token and token amounts out.
        // We copy that information to memory to return it before it is deleted during settlement.
        tokensOut = _currentSwapTokensOut._values;
        amountsOut = new uint256[](tokensOut.length);
        for (uint256 i = 0; i < tokensOut.length; ++i) {
            amountsOut[i] = _currentSwapTokenOutAmounts[tokensOut[i]] + _settledTokenAmounts[tokensOut[i]];
            _settledTokenAmounts[tokensOut[i]] = 0;
        }

        _settlePaths(params.sender, params.wethIsEth);
    }

    function _swapExactInHook(
        SwapExactInHookParams calldata params
    ) internal returns (uint256[] memory pathAmountsOut) {
        pathAmountsOut = new uint256[](params.paths.length);

        for (uint256 i = 0; i < params.paths.length; ++i) {
            SwapPathExactAmountIn memory path = params.paths[i];
            // These two variables shall be updated at the end of each step to be used as inputs of the next one.
            // The initial values are the given token and amount in for the current path.
            uint256 stepExactAmountIn = path.exactAmountIn;
            IERC20 stepTokenIn = path.tokenIn;

            // TODO: this should be transient.
            // Paths may (or may not) share the same token in. To minimize token transfers, we store the addresses in
            // a set with unique addresses that can be iterated later on.
            // For example, if all paths share the same token in, the set will end up with only one entry.
            _currentSwapTokensIn.add(address(stepTokenIn));
            _currentSwapTokenInAmounts[address(stepTokenIn)] += stepExactAmountIn;

            for (uint256 j = 0; j < path.steps.length; ++j) {
                bool isLastStep = (j == path.steps.length - 1);
                uint256 minAmountOut;

                // minAmountOut only applies to the last step.
                if (isLastStep) {
                    minAmountOut = path.minAmountOut;
                } else {
                    minAmountOut = 0;
                }

                SwapPathStep memory step = path.steps[j];

                if (address(stepTokenIn) == step.pool) {
                    // Remove liquidity is not transient when it comes to BPT, meaning the caller needs to have the
                    // required amount when performing the operation. These tokens might be the output of a previous
                    // step, in which case the user will have a BPT credit.
                    if (IVault(_vault).getTokenDelta(address(this), stepTokenIn) < 0) {
                        _vault.sendTo(IERC20(step.pool), params.sender, stepExactAmountIn);
                    }
                    // BPT is burnt instantly, so we don't need to send it back later.
                    if (_currentSwapTokenInAmounts[address(stepTokenIn)] > 0) {
                        _currentSwapTokenInAmounts[address(stepTokenIn)] -= stepExactAmountIn;
                    }

                    // Token in is BPT: remove liquidity - Single token exact in
                    // minAmountOut cannot be 0 in this case, as that would send an array of 0s to the Vault, which
                    // wouldn't know which token to use.
                    (uint256[] memory amountsOut, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
                        step.pool,
                        step.tokenOut,
                        minAmountOut == 0 ? 1 : minAmountOut
                    );

                    // Reusing `amountsOut` as input argument and function output to prevent stack too deep error.
                    (, amountsOut, ) = _vault.removeLiquidity(
                        RemoveLiquidityParams({
                            pool: step.pool,
                            from: params.sender,
                            maxBptAmountIn: stepExactAmountIn,
                            minAmountsOut: amountsOut,
                            kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                            userData: params.userData
                        })
                    );

                    if (isLastStep) {
                        // The amount out for the last step of the path should be recorded for the return value, and the
                        // amount for the token should be sent back to the sender later on.
                        pathAmountsOut[i] = amountsOut[tokenIndex];
                        _currentSwapTokensOut.add(address(step.tokenOut));
                        _currentSwapTokenOutAmounts[address(step.tokenOut)] += amountsOut[tokenIndex];
                    } else {
                        // Input for the next step is output of current step.
                        stepExactAmountIn = amountsOut[tokenIndex];
                        // The token in for the next step is the token out of the current step.
                        stepTokenIn = step.tokenOut;
                    }
                } else if (address(step.tokenOut) == step.pool) {
                    // Token out is BPT: add liquidity - Single token exact in (unbalanced)
                    (uint256[] memory exactAmountsIn, ) = _getSingleInputArrayAndTokenIndex(
                        step.pool,
                        stepTokenIn,
                        stepExactAmountIn
                    );

                    (, uint256 bptAmountOut, ) = _vault.addLiquidity(
                        AddLiquidityParams({
                            pool: step.pool,
                            to: params.sender,
                            maxAmountsIn: exactAmountsIn,
                            minBptAmountOut: minAmountOut,
                            kind: AddLiquidityKind.UNBALANCED,
                            userData: params.userData
                        })
                    );

                    if (isLastStep) {
                        // The amount out for the last step of the path should be recorded for the return value.
                        // We do not need to register the amount out in _currentSwapTokenOutAmounts since the BPT
                        // is minted directly to the sender, so this step can be considered settled at this point.
                        pathAmountsOut[i] = bptAmountOut;
                        _currentSwapTokensOut.add(address(step.tokenOut));
                        _settledTokenAmounts[address(step.tokenOut)] += bptAmountOut;
                    } else {
                        // Input for the next step is output of current step.
                        stepExactAmountIn = bptAmountOut;
                        // The token in for the next step is the token out of the current step.
                        stepTokenIn = step.tokenOut;
                        // If this is an intermediate step, we'll need to send it back to the vault
                        // to get credit for the BPT minted in the add liquidity operation.
                        _vault.takeFrom(IERC20(step.pool), params.sender, bptAmountOut);
                    }
                } else {
                    // No BPT involved in the operation: regular swap exact in
                    (, , uint256 amountOut) = _vault.swap(
                        SwapParams({
                            kind: SwapKind.EXACT_IN,
                            pool: step.pool,
                            tokenIn: stepTokenIn,
                            tokenOut: step.tokenOut,
                            amountGivenRaw: stepExactAmountIn,
                            limitRaw: minAmountOut,
                            userData: params.userData
                        })
                    );

                    if (isLastStep) {
                        // The amount out for the last step of the path should be recorded for the return value, and the
                        // amount for the token should be sent back to the sender later on.
                        pathAmountsOut[i] = amountOut;
                        _currentSwapTokensOut.add(address(step.tokenOut));
                        _currentSwapTokenOutAmounts[address(step.tokenOut)] += amountOut;
                    } else {
                        // Input for the next step is output of current step.
                        stepExactAmountIn = amountOut;
                        // The token in for the next step is the token out of the current step.
                        stepTokenIn = step.tokenOut;
                    }
                }
            }
        }
    }

    function swapExactOutHook(
        SwapExactOutHookParams calldata params
    )
        external
        payable
        nonReentrant
        onlyVault
        returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn)
    {
        pathAmountsIn = _swapExactOutHook(params);

        // The hook writes current swap token and token amounts in.
        // We copy that information to memory to return it before it is deleted during settlement.
        tokensIn = _currentSwapTokensIn._values; // Copy transient storage to memory
        amountsIn = new uint256[](tokensIn.length);
        for (uint256 i = 0; i < tokensIn.length; ++i) {
            amountsIn[i] = _currentSwapTokenInAmounts[tokensIn[i]] + _settledTokenAmounts[tokensIn[i]];
            _settledTokenAmounts[tokensIn[i]] = 0;
        }

        _settlePaths(params.sender, params.wethIsEth);
    }

    /**
     * @dev Executes every swap path in the given input parameters.
     * Computes inputs for the path, and aggregates them by token and amounts as well in transient storage.
     */
    function _swapExactOutHook(
        SwapExactOutHookParams calldata params
    ) internal returns (uint256[] memory pathAmountsIn) {
        pathAmountsIn = new uint256[](params.paths.length);

        for (uint256 i = 0; i < params.paths.length; ++i) {
            SwapPathExactAmountOut memory path = params.paths[i];
            // This variable shall be updated at the end of each step to be used as input of the next one.
            // The first value corresponds to the given amount out for the current path.
            uint256 stepExactAmountOut = path.exactAmountOut;

            // Paths may (or may not) share the same token in. To minimize token transfers, we store the addresses in
            // a set with unique addresses that can be iterated later on.
            // For example, if all paths share the same token in, the set will end up with only one entry.
            // Since the path is 'given out', the output of the operation specified by the last step in each path will
            // be added to calculate the amounts in for each token.
            // TODO: this should be transient
            _currentSwapTokensIn.add(address(path.tokenIn));

            // Backwards iteration: the exact amount out applies to the last step, so we cannot iterate from first to
            // last. The calculated input of step (j) is the exact amount out for step (j - 1).
            for (int256 j = int256(path.steps.length - 1); j >= 0; --j) {
                SwapPathStep memory step = path.steps[uint256(j)];
                bool isLastStep = (j == 0);

                // These two variables are set at the beginning of the iteration and are used as inputs for
                // the operation described by the step.
                uint256 stepMaxAmountIn;
                IERC20 stepTokenIn;

                // Stack too deep
                {
                    bool isFirstStep = (uint256(j) == path.steps.length - 1);

                    if (isFirstStep) {
                        // The first step in the iteration is the last one in the given array of steps, and it
                        // specifies the output token for the step as well as the exact amount out for that token.
                        // Output amounts are stored to send them later on.
                        // TODO: This should be transient.
                        _currentSwapTokensOut.add(address(step.tokenOut));
                        _currentSwapTokenOutAmounts[address(step.tokenOut)] += stepExactAmountOut;
                    }

                    if (isLastStep) {
                        // In backwards order, the last step is the first one in the given path.
                        // The given token in and max amount in apply for this step.
                        stepMaxAmountIn = path.maxAmountIn;
                        stepTokenIn = path.tokenIn;
                    } else {
                        // For every other intermediate step, no maximum input applies.
                        // The input token for this step is the output token of the previous given step.
                        // We use uint128 to prevent Vault's internal scaling from overflowing.
                        stepMaxAmountIn = type(uint128).max;
                        stepTokenIn = path.steps[uint256(j - 1)].tokenOut;
                    }
                }

                if (address(stepTokenIn) == step.pool) {
                    // Remove liquidity is not transient when it comes to BPT, meaning the caller needs to have the
                    // required amount when performing the operation. In this case, the BPT amount needed for the
                    // operation is not known in advance, so we take a flashloan for all the available reserves.
                    // The last step is the one that defines the inputs for this path. The caller should have enough
                    // BPT to burn already if that's the case, so we just skip this step if so.
                    if (isLastStep == false) {
                        stepMaxAmountIn = _vault.getTokenReserve(stepTokenIn);
                        _vault.sendTo(IERC20(step.pool), params.sender, stepMaxAmountIn);
                    }

                    // Token in is BPT: remove liquidity - Single token exact out
                    (uint256[] memory exactAmountsOut, ) = _getSingleInputArrayAndTokenIndex(
                        step.pool,
                        step.tokenOut,
                        stepExactAmountOut
                    );

                    (uint256 bptAmountIn, , ) = _vault.removeLiquidity(
                        RemoveLiquidityParams({
                            pool: step.pool,
                            from: params.sender,
                            maxBptAmountIn: stepMaxAmountIn,
                            minAmountsOut: exactAmountsOut,
                            kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                            userData: params.userData
                        })
                    );

                    if (isLastStep) {
                        // BPT is burnt instantly, so we don't need to send it to the Vault during settlement.
                        pathAmountsIn[i] = bptAmountIn;
                        _settledTokenAmounts[address(stepTokenIn)] += bptAmountIn;
                    } else {
                        // Output for the step (j - 1) is the input of step (j).
                        stepExactAmountOut = bptAmountIn;
                        // Refund unused portion of BPT flashloan to the Vault
                        if (bptAmountIn < stepMaxAmountIn) {
                            _vault.takeFrom(stepTokenIn, params.sender, stepMaxAmountIn - bptAmountIn);
                        }
                    }
                } else if (address(step.tokenOut) == step.pool) {
                    // Token out is BPT: add liquidity - Single token exact out
                    (uint256[] memory stepAmountsIn, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
                        step.pool,
                        stepTokenIn,
                        stepMaxAmountIn
                    );

                    // Reusing `amountsIn` as input argument and function output to prevent stack too deep error.
                    (stepAmountsIn, , ) = _vault.addLiquidity(
                        AddLiquidityParams({
                            pool: step.pool,
                            to: params.sender,
                            maxAmountsIn: stepAmountsIn,
                            minBptAmountOut: stepExactAmountOut,
                            kind: AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                            userData: params.userData
                        })
                    );

                    if (isLastStep) {
                        // The amount out for the last step of the path should be recorded for the return value.
                        pathAmountsIn[i] = stepAmountsIn[tokenIndex];
                        _currentSwapTokenInAmounts[address(stepTokenIn)] += stepAmountsIn[tokenIndex];
                    } else {
                        stepExactAmountOut = stepAmountsIn[tokenIndex];
                    }

                    // stack-too-deep
                    {
                        // The last step given determines the outputs for the path. Since this is given out, the last
                        // step given is the first one to be executed in the loop.
                        bool isFirstStep = (uint256(j) == path.steps.length - 1);
                        if (isFirstStep) {
                            // Instead of sending tokens back to the vault, we can just discount it from whatever
                            // the vault owes the sender to make one less transfer.
                            _currentSwapTokenOutAmounts[address(step.tokenOut)] -= stepExactAmountOut;
                        } else {
                            _vault.takeFrom(IERC20(step.pool), params.sender, stepExactAmountOut);
                        }
                    }
                } else {
                    // No BPT involved in the operation: regular swap exact out
                    (, uint256 amountIn, ) = _vault.swap(
                        SwapParams({
                            kind: SwapKind.EXACT_OUT,
                            pool: step.pool,
                            tokenIn: stepTokenIn,
                            tokenOut: step.tokenOut,
                            amountGivenRaw: stepExactAmountOut,
                            limitRaw: stepMaxAmountIn,
                            userData: params.userData
                        })
                    );

                    if (isLastStep) {
                        pathAmountsIn[i] = amountIn;
                        _currentSwapTokenInAmounts[address(stepTokenIn)] += amountIn;
                    } else {
                        stepExactAmountOut = amountIn;
                    }
                }
            }
        }
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
                            deadline: type(uint256).max,
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
                            limit: type(uint256).max,
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
    function queryAddLiquidityUnbalanced(
        address pool,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
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
                        minBptAmountOut: minBptAmountOut,
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
        uint256 maxAmountIn,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) external returns (uint256 amountIn) {
        (uint256[] memory maxAmountsIn, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
            pool,
            tokenIn,
            maxAmountIn
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
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut) {
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
        uint256 minAmountOut,
        bytes memory userData
    ) external returns (uint256 amountOut) {
        (uint256[] memory minAmountsOut, uint256 tokenIndex) = _getSingleInputArrayAndTokenIndex(
            pool,
            tokenOut,
            minAmountOut
        );

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
        uint256 maxBptAmountIn,
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
                        maxBptAmountIn: maxBptAmountIn,
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

    /**
     * @dev Returns excess ETH back to the contract caller, assuming `amountUsed` has been spent. Reverts
     * if the caller sent less ETH than `amountUsed`.
     *
     * Because the caller might not know exactly how much ETH a Vault action will require, they may send extra.
     * Note that this excess value is returned *to the contract caller* (msg.sender). If caller and e.g. swap sender are
     * not the same (because the caller is a relayer for the sender), then it is up to the caller to manage this
     * returned ETH.
     */
    function _returnEth(address sender, uint256 amountUsed) internal {
        if (msg.value < amountUsed) {
            revert InsufficientEth();
        }

        uint256 excess = msg.value - amountUsed;
        if (excess > 0) {
            payable(sender).sendValue(excess);
        }
    }

    /**
     * @dev Enables the Router to receive ETH. This is required for it to be able to unwrap WETH, which sends ETH to the
     * caller.
     *
     * Any ETH sent to the Router outside of the WETH unwrapping mechanism would be forever locked inside the Router, so
     * we prevent that from happening. Other mechanisms used to send ETH to the Router (such as being the recipient of
     * an ETH swap, Pool exit or withdrawal, contract self-destruction, or receiving the block mining reward) will
     * result in locked funds, but are not otherwise a security or soundness issue. This check only exists as an attempt
     * to prevent user error.
     */
    receive() external payable {
        if (msg.sender != address(_weth)) {
            revert EthTransfer();
        }
    }

    /**
     * @dev Returns an array with `amountGiven` at `tokenIndex`, and 0 for every other index.
     * The returned array length matches the number of tokens in the pool.
     * Reverts if the given index is greater than or equal to the pool number of tokens.
     */
    function _getSingleInputArrayAndTokenIndex(
        address pool,
        IERC20 token,
        uint256 amountGiven
    ) internal view returns (uint256[] memory amountsGiven, uint256 tokenIndex) {
        uint256 numTokens;
        (numTokens, tokenIndex) = _vault.getPoolTokenCountAndIndexOfToken(pool, token);
        amountsGiven = new uint256[](numTokens);
        amountsGiven[tokenIndex] = amountGiven;
    }

    function _takeTokenIn(
        address sender,
        IERC20 tokenIn,
        uint256 amountIn,
        bool wethIsEth
    ) internal returns (uint256 ethAmountIn) {
        // If the tokenIn is ETH, then wrap `amountIn` into WETH.
        if (wethIsEth && tokenIn == _weth) {
            ethAmountIn = amountIn;
            // wrap amountIn to WETH
            _weth.deposit{ value: amountIn }();
            // send WETH to Vault
            _weth.transfer(address(_vault), amountIn);
            // update Vault accounting
            _vault.settle(_weth);
        } else {
            // Send the tokenIn amount to the Vault
            _vault.takeFrom(tokenIn, sender, amountIn);
        }
    }

    function _sendTokenOut(address sender, IERC20 tokenOut, uint256 amountOut, bool wethIsEth) internal {
        // If the tokenOut is ETH, then unwrap `amountOut` into ETH.
        if (wethIsEth && tokenOut == _weth) {
            // Receive the WETH amountOut
            _vault.sendTo(tokenOut, address(this), amountOut);
            // Withdraw WETH to ETH
            _weth.withdraw(amountOut);
            // Send ETH to sender
            payable(sender).sendValue(amountOut);
        } else {
            // Receive the tokenOut amountOut
            _vault.sendTo(tokenOut, sender, amountOut);
        }
    }

    function _settlePaths(address sender, bool wethIsEth) internal {
        // numTokensIn / Out may be 0 if the inputs and / or outputs are not transient.
        // For example, a swap starting with a 'remove liquidity' step will already have burned the input tokens,
        // in which case there is nothing to settle. Then, since we're iterating backwards below, we need to be able
        // to subtract 1 from these quantities without reverting, which is why we use signed integers.
        int256 numTokensIn = int256(_currentSwapTokensIn.length());
        int256 numTokensOut = int256(_currentSwapTokensOut.length());
        uint256 ethAmountIn = 0;

        // Iterate backwards, from the last element to 0 (included).
        // Removing the last element from a set is cheaper than removing the first one.
        for (int256 i = int256(numTokensIn - 1); i >= 0; --i) {
            address tokenIn = _currentSwapTokensIn.unchecked_at(uint256(i));
            ethAmountIn += _takeTokenIn(sender, IERC20(tokenIn), _currentSwapTokenInAmounts[tokenIn], wethIsEth);

            _currentSwapTokensIn.remove(tokenIn);
            _currentSwapTokenInAmounts[tokenIn] = 0;
        }

        for (int256 i = int256(numTokensOut - 1); i >= 0; --i) {
            address tokenOut = _currentSwapTokensOut.unchecked_at(uint256(i));
            _sendTokenOut(sender, IERC20(tokenOut), _currentSwapTokenOutAmounts[tokenOut], wethIsEth);

            _currentSwapTokensOut.remove(tokenOut);
            _currentSwapTokenOutAmounts[tokenOut] = 0;
        }

        // Return the rest of ETH to sender
        _returnEth(sender, ethAmountIn);
    }
}
