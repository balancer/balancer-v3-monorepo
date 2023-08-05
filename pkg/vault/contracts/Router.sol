// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { Asset, AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ReentrancyGuard } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import "forge-std/Test.sol";

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

    function addLiquidityCallback(AddLiquidityCallbackParams calldata params)
        external
        payable
        nonReentrant
        returns (uint256[] memory amountsIn, uint256 bptAmountOut)
    {
        IERC20[] memory tokens = params.assets.toIERC20(_weth);

        (amountsIn, bptAmountOut) = _vault.addLiquidity(
            params.pool,
            tokens,
            params.maxAmountsIn,
            params.minBptAmountOut,
            params.userData
        );

        // We need to track how much of the received ETH was used and wrapped into WETH to return any excess.
        uint256 wrappedEth = 0;

        for (uint256 i = 0; i < params.assets.length; ++i) {
            // Receive assets from the handler
            Asset asset = params.assets[i];
            uint256 amountIn = amountsIn[i];

            IERC20 token = asset.toIERC20(_weth);

            if (asset.isETH()) {
                _weth.deposit{ value: amountIn }();
                wrappedEth = wrappedEth + amountIn;
            }
            _vault.retrieve(token, params.sender, amountIn);
        }

        _vault.mint(IERC20(params.pool), params.sender, bptAmountOut);

        // Send remaining ETH to the user
        address(params.sender).returnEth(wrappedEth);
    }

    function removeLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData
    ) external nonReentrant returns (uint256[] memory amountsOut) {
        IERC20[] memory tokens = assets.toIERC20(_weth);

        amountsOut = _vault.removeLiquidity(pool, tokens, minAmountsOut, bptAmountIn, userData);

        for (uint256 i = 0; i < assets.length; ++i) {
            uint256 amountOut = amountsOut[i];

            // Send tokens to the recipient
            assets[i].send(msg.sender, amountOut, _weth);
            // TODO:  Handle ETH properly
        }

        _vault.burn(IERC20(pool), msg.sender, bptAmountIn);
    }

    function swap(SingleSwap calldata params) external payable nonReentrant returns (uint256) {
        IERC20 tokenIn = params.assetIn.toIERC20(_weth);
        IERC20 tokenOut = params.assetOut.toIERC20(_weth);

        (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) = _vault.swap(
            IVault.SwapParams({
                kind: params.kind,
                pool: params.pool,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountGiven: params.amountGiven,
                limit: params.limit,
                deadline: params.deadline,
                userData: params.userData
            })
        );

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
            _vault.retrieve(tokenIn, msg.sender, amountIn);
        }

        // If the assetOut is ETH, then unwrap `amountOut` into ETH.
        if (params.assetOut.isETH()) {
            // Receive the WETH amountOut
            _vault.send(tokenOut, address(this), amountOut);
            // Withdraw WETH to ETH
            _weth.withdraw(amountOut);
            // Send ETH to msg.sender
            payable(msg.sender).sendValue(amountOut);
        } else {
            // Receive the tokenOut amountOut
            _vault.send(tokenOut, msg.sender, amountOut);
        }

        if (params.assetIn.isETH()) {
            // Return the rest of ETH to sender
            address(msg.sender).returnEth(amountIn);
        }

        return amountCalculated;
    }
}
