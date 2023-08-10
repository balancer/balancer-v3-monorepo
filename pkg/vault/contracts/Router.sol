// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { Asset, AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ReentrancyGuard } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

contract Router is IRouter, ReentrancyGuard {
    using AssetHelpers for *;
    using Address for address payable;

    IVault private immutable _vault;

    // solhint-disable-next-line var-name-mixedcase
    IWETH private immutable _weth;

    constructor(IVault vault, address weth) {
        _vault = vault;
        _weth = IWETH(weth);
    }

    function addLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        return
            abi.decode(
                _vault.invoke(
                    abi.encodeWithSelector(
                        Router.addLiquidityCallback.selector,
                        AddLiquidityCallbackParams({
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

    function addLiquidityCallback(
        AddLiquidityCallbackParams calldata params
    ) external payable nonReentrant returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        IERC20[] memory tokens = params.assets.toIERC20(_weth);

        (amountsIn, bptAmountOut) = _vault.addLiquidity(
            params.pool,
            tokens,
            params.maxAmountsIn,
            params.minBptAmountOut,
            params.userData
        );

        for (uint256 i = 0; i < params.assets.length; ++i) {
            // Receive assets from the handler
            Asset asset = params.assets[i];
            uint256 amountIn = amountsIn[i];

            IERC20 token = asset.toIERC20(_weth);

            // There can be only one WETH token in the pool
            if (asset.isETH()) {
                _weth.deposit{ value: amountIn }();
                address(params.sender).returnEth(amountIn);
            }
            _vault.retrieve(token, params.sender, amountIn);
        }

        _vault.mint(IERC20(params.pool), params.sender, bptAmountOut);

        // Send remaining ETH to the user
    }

    function removeLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut) {
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
                            bptAmountIn: bptAmountIn,
                            userData: userData
                        })
                    )
                ),
                (uint256[])
            );
    }

    function removeLiquidityCallback(
        RemoveLiquidityCallbackParams calldata params
    ) external nonReentrant returns (uint256[] memory amountsOut) {
        IERC20[] memory tokens = params.assets.toIERC20(_weth);

        amountsOut = _vault.removeLiquidity(
            params.pool,
            tokens,
            params.minAmountsOut,
            params.bptAmountIn,
            params.userData
        );

        for (uint256 i = 0; i < params.assets.length; ++i) {
            uint256 amountOut = amountsOut[i];

            Asset asset = params.assets[i];
            IERC20 token = asset.toIERC20(_weth);

            // Receive the asset amountOut
            _vault.wire(token, params.sender, amountOut);

            // There can be only one WETH token in the pool
            if (asset.isETH()) {
                // Withdraw WETH to ETH
                _weth.withdraw(amountOut);
                // Send ETH to sender
                payable(params.sender).sendValue(amountOut);
            }
        }

        _vault.burn(IERC20(params.pool), params.sender, params.bptAmountIn);
    }

    function swap(
        IVault.SwapKind kind,
        address pool,
        Asset assetIn,
        Asset assetOut,
        uint256 amountGiven,
        uint256 limit,
        uint256 deadline,
        bytes calldata userData
    ) external payable returns (uint256 amountCalculated) {
        return
            abi.decode(
                _vault.invoke(
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

    function swapCallback(SwapCallbackParams calldata params) external payable nonReentrant returns (uint256) {
        //TODO: check sender is vault
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > params.deadline) {
            revert IVaultErrors.SwapDeadline();
        }

        IERC20 tokenIn = params.assetIn.toIERC20(_weth);
        IERC20 tokenOut = params.assetOut.toIERC20(_weth);

        (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) = _vault.swap(
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
            revert IVaultErrors.SwapLimit(params.kind == IVault.SwapKind.GIVEN_IN ? amountOut : amountIn, params.limit);
        }

        // If the assetIn is ETH, then wrap `amountIn` into WETH.
        if (params.assetIn.isETH()) {
            // wrap amountIn to WETH
            _weth.deposit{ value: amountIn }();
            // send WETH to Vault
            _weth.transfer(address(_vault), amountIn);
            // update Vault accouting
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

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    function queryAddLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        try
            _vault.invoke(
                abi.encodeWithSelector(
                    Router.addLiquidityCallback.selector,
                    AddLiquidityCallbackParams({
                        sender: msg.sender,
                        pool: pool,
                        assets: assets,
                        maxAmountsIn: maxAmountsIn,
                        minBptAmountOut: minBptAmountOut,
                        userData: userData
                    })
                )
            )
        {
            // solhint-disable-previous-line no-empty-blocks
            // This block will always fail, as the design of the swap query ensures it never returns normally.
            // Instead, it will either throw an error or provide the desired value in the error message.
        } catch (bytes memory reason) {
            // If the reason (error message) isn't 32 bytes long, it's assumed to be a string error message
            // and the transaction is reverted with that message.
            if (reason.length != 0x20) {
                // The easiest way to bubble the revert reason is using memory via assembly
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    revert(add(32, reason), mload(reason))
                }
            }

            // If the reason is 32 bytes long, it's assumed to be the desired return value and is decoded and returned.
            return abi.decode(reason, (uint256[], uint256));
        }
    }

    function addLiquidityCallback(
        AddLiquidityCallbackParams calldata params
    ) external payable nonReentrant returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        IERC20[] memory tokens = params.assets.toIERC20(_weth);

        (amountsIn, bptAmountOut) = _vault.addLiquidity(
            params.pool,
            tokens,
            params.maxAmountsIn,
            params.minBptAmountOut,
            params.userData
        );

        for (uint256 i = 0; i < params.assets.length; ++i) {
            // Receive assets from the handler
            Asset asset = params.assets[i];
            uint256 amountIn = amountsIn[i];

            IERC20 token = asset.toIERC20(_weth);

            // There can be only one WETH token in the pool
            if (asset.isETH()) {
                _weth.deposit{ value: amountIn }();
                address(params.sender).returnEth(amountIn);
            }
            _vault.retrieve(token, params.sender, amountIn);
        }

        _vault.mint(IERC20(params.pool), params.sender, bptAmountOut);

        // Send remaining ETH to the user
    }

    /// @inheritdoc IRouter
    function querySwap(
        IVault.SwapKind kind,
        address pool,
        Asset assetIn,
        Asset assetOut,
        uint256 amountGiven,
        bytes calldata userData
    ) external payable returns (uint256 amountCalculated) {
        // Invoking querySwapCallback via the _vault contract.
        try
            _vault.invoke(
                // Encode the function call to the Router's querySwapCallback function, with all necessary parameters.
                abi.encodeWithSelector(
                    Router.querySwapCallback.selector,
                    kind,
                    pool,
                    assetIn,
                    assetOut,
                    amountGiven,
                    userData
                )
            )
        {
            // solhint-disable-previous-line no-empty-blocks
            // This block will always fail, as the design of the swap query ensures it never returns normally.
            // Instead, it will either throw an error or provide the desired value in the error message.
        } catch (bytes memory reason) {
            // If the reason (error message) isn't 32 bytes long, it's assumed to be a string error message
            // and the transaction is reverted with that message.
            if (reason.length != 0x20) {
                // The easiest way to bubble the revert reason is using memory via assembly
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    revert(add(32, reason), mload(reason))
                }
            }

            // If the reason is 32 bytes long, it's assumed to be the desired return value and is decoded and returned.
            return abi.decode(reason, (uint256));
        }
    }

    function querySwapCallback(
        IVault.SwapKind kind,
        address pool,
        Asset assetIn,
        Asset assetOut,
        uint256 amountGiven,
        bytes calldata userData
    ) external payable nonReentrant {
        IERC20 tokenIn = assetIn.toIERC20(_weth);
        IERC20 tokenOut = assetOut.toIERC20(_weth);

        // TODO: try catch revert with custom reason
        // check that call does not reverting
        // if it reverts then add the prefix with right prefix
        (uint256 amountCalculated, , ) = _vault.swap(
            IVault.SwapParams({
                kind: kind,
                pool: pool,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountGiven: amountGiven,
                userData: userData
            })
        );

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Load the free memory pointer address
            let ptr := mload(0x40)

            // Store the value of `amountCalculated` at the address pointed by `ptr`
            mstore(ptr, amountCalculated)

            // Revert the transaction with `amountCalculated` as the error message
            // The message is of length x20 (32 bytes in hexadecimal notation)
            revert(ptr, 0x20)
        }
    }
}
