// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { RebalanceHookParams } from "@balancer-labs/v3-interfaces/contracts/vault/IBufferPool.sol";

import { ERC4626BufferPool } from "@balancer-labs/v3-vault/contracts/ERC4626BufferPool.sol";
import { BasePoolHooks } from "@balancer-labs/v3-vault/contracts/BasePoolHooks.sol";

contract ERC4626BufferPoolMock is ERC4626BufferPool {
    constructor(
        string memory name,
        string memory symbol,
        IERC4626 wrappedToken,
        IVault vault
    ) ERC4626BufferPool(name, symbol, wrappedToken, vault) {}

    // If EXACT_IN, assets will be wrapped. Else, assets will be unwrapped
    function unbalanceThePool(uint256 assetsToTransfer, SwapKind kind) external {
        uint8 indexIn = kind == SwapKind.EXACT_IN ? 1 : 0;
        uint8 indexOut = kind == SwapKind.EXACT_IN ? 0 : 1;
        uint256 limit = kind == SwapKind.EXACT_IN ? assetsToTransfer / 2 : assetsToTransfer * 2;

        (IERC20[] memory tokens, , , , ) = getVault().getPoolTokenInfo(address(this));

        getVault().invoke(
            abi.encodeWithSelector(
                ERC4626BufferPoolMock.unbalanceHook.selector,
                RebalanceHookParams({
                    sender: msg.sender,
                    kind: kind,
                    pool: address(this),
                    tokenIn: tokens[indexIn],
                    tokenOut: tokens[indexOut],
                    amountGiven: assetsToTransfer,
                    limit: limit
                })
            )
        );
    }

    function unbalanceHook(RebalanceHookParams calldata params) external payable onlyVault {
        (, uint256 amountIn, uint256 amountOut) = _swapHook(params);

        if (params.kind == SwapKind.EXACT_IN) {
            IERC20 underlyingToken = params.tokenIn;
            IERC20 wrappedToken = params.tokenOut;

            getVault().wire(wrappedToken, address(this), amountOut);
            IERC4626(address(wrappedToken)).withdraw(amountIn, address(this), address(this));
            underlyingToken.approve(address(getVault()), amountIn);
            getVault().retrieve(underlyingToken, address(this), amountIn);
        } else {
            IERC20 underlyingToken = params.tokenOut;
            IERC20 wrappedToken = params.tokenIn;

            getVault().wire(underlyingToken, address(this), amountOut);
            underlyingToken.approve(address(wrappedToken), amountOut);
            IERC4626(address(wrappedToken)).deposit(amountOut, address(this));
            wrappedToken.approve(address(getVault()), amountIn);
            getVault().retrieve(wrappedToken, address(this), amountIn);
        }
    }
}
