// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { SwapKind, SwapParams as VaultSwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ERC4626BufferPool } from "@balancer-labs/v3-vault/contracts/ERC4626BufferPool.sol";
import { BasePoolHooks } from "@balancer-labs/v3-vault/contracts/BasePoolHooks.sol";

contract ERC4626BufferPoolMock is ERC4626BufferPool {
    using SafeERC20 for IERC20;

    constructor(
        string memory name,
        string memory symbol,
        IERC4626 wrappedToken,
        IVault vault
    ) ERC4626BufferPool(name, symbol, wrappedToken, vault) {}

    // If EXACT_IN, assets will be wrapped. Else, assets will be unwrapped
    function unbalanceThePool(uint256 assetsToTransferRaw, SwapKind kind) external {
        (IERC20[] memory tokens, , , , ) = getVault().getPoolTokenInfo(address(this));

        uint256 indexIn = kind == SwapKind.EXACT_IN ? _baseTokenIndex : _wrappedTokenIndex;
        uint256 indexOut = kind == SwapKind.EXACT_IN ? _wrappedTokenIndex : _baseTokenIndex;

        uint256 limit = _wrappedToken.convertToShares(assetsToTransferRaw);

        // Since it's a normal swap, it's passing through linear math and the rates have more errors.
        // Limiting the slippage to 1% of the calculated wrapped amount out, for testing purposes
        if (kind == SwapKind.EXACT_IN) {
            limit -= limit / 100;
        } else {
            limit += limit / 100;
        }

        getVault().lock(
            abi.encodeWithSelector(
                ERC4626BufferPoolMock.unbalanceHook.selector,
                VaultSwapParams({
                    kind: kind,
                    pool: address(this),
                    tokenIn: tokens[indexIn],
                    tokenOut: tokens[indexOut],
                    amountGivenRaw: assetsToTransferRaw,
                    limitRaw: limit,
                    userData: ""
                })
            )
        );
    }

    function unbalanceHook(VaultSwapParams calldata params) external onlyVault {
        (, uint256 amountIn, uint256 amountOut) = _swapHook(params);

        IERC20 underlyingToken;
        IERC20 wrappedToken;
        if (params.kind == SwapKind.EXACT_IN) {
            underlyingToken = params.tokenIn;
            wrappedToken = params.tokenOut;

            getVault().sendTo(wrappedToken, address(this), amountOut);
            IERC4626(address(wrappedToken)).withdraw(amountIn, address(this), address(this));
            underlyingToken.safeTransfer(address(getVault()), amountIn);
            getVault().settle(underlyingToken);
        } else {
            underlyingToken = params.tokenOut;
            wrappedToken = params.tokenIn;

            getVault().sendTo(underlyingToken, address(this), amountOut);
            underlyingToken.approve(address(wrappedToken), amountOut);
            IERC4626(address(wrappedToken)).deposit(amountOut, address(this));
            wrappedToken.safeTransfer(address(getVault()), amountIn);
            getVault().settle(wrappedToken);
        }
    }
}
