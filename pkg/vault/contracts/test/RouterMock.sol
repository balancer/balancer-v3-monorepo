// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { RawCallHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/RawCallHelpers.sol";

import "../Router.sol";

contract RouterMock is Router {
    error MockErrorCode();

    constructor(IVault vault, IWETH weth) Router(vault, weth) {}

    function getSingleInputArrayAndTokenIndex(
        address pool,
        IERC20 token,
        uint256 amountGiven
    ) external view returns (uint256[] memory amountsGiven, uint256 tokenIndex) {
        return _getSingleInputArrayAndTokenIndex(pool, token, amountGiven);
    }

    function querySwapSingleTokenExactInAndRevert(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        bytes calldata userData
    ) external returns (uint256 amountCalculated) {
        (bool success, bytes memory resultRaw) = address(_vault).call(
            abi.encodeWithSelector(
                IVaultExtension.quoteAndRevert.selector,
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
            )
        );

        return abi.decode(RawCallHelpers.unwrapRawCallResult(success, resultRaw), (uint256));
    }

    function querySpoof() external returns (uint256) {
        (bool success, bytes memory resultRaw) = address(_vault).call(
            abi.encodeWithSelector(
                IVaultExtension.quoteAndRevert.selector,
                abi.encodeWithSelector(RouterMock.querySpoofHook.selector)
            )
        );

        return abi.decode(RawCallHelpers.unwrapRawCallResult(success, resultRaw), (uint256));
    }

    function querySpoofHook() external pure {
        revert RawCallHelpers.Result(abi.encode(uint256(1234)));
    }

    function queryRevertErrorCode() external returns (uint256) {
        (bool success, bytes memory resultRaw) = address(_vault).call(
            abi.encodeWithSelector(
                IVaultExtension.quoteAndRevert.selector,
                abi.encodeWithSelector(RouterMock.queryRevertErrorCodeHook.selector)
            )
        );

        return abi.decode(RawCallHelpers.unwrapRawCallResult(success, resultRaw), (uint256));
    }

    function queryRevertErrorCodeHook() external pure {
        revert MockErrorCode();
    }

    function queryRevertLegacy() external returns (uint256) {
        (bool success, bytes memory resultRaw) = address(_vault).call(
            abi.encodeWithSelector(
                IVaultExtension.quoteAndRevert.selector,
                abi.encodeWithSelector(RouterMock.queryRevertLegacyHook.selector)
            )
        );

        return abi.decode(RawCallHelpers.unwrapRawCallResult(success, resultRaw), (uint256));
    }

    function queryRevertLegacyHook() external pure {
        revert("Legacy revert reason");
    }

    function queryRevertPanic() external returns (uint256) {
        (bool success, bytes memory resultRaw) = address(_vault).call(
            abi.encodeWithSelector(
                IVaultExtension.quoteAndRevert.selector,
                abi.encodeWithSelector(RouterMock.queryRevertPanicHook.selector)
            )
        );

        return abi.decode(RawCallHelpers.unwrapRawCallResult(success, resultRaw), (uint256));
    }

    function queryRevertPanicHook() external pure returns (uint256) {
        uint256 a = 10;
        uint256 b = 0;
        return a / b;
    }

    function queryRevertNoReason() external returns (uint256) {
        (bool success, bytes memory resultRaw) = address(_vault).call(
            abi.encodeWithSelector(
                IVaultExtension.quoteAndRevert.selector,
                abi.encodeWithSelector(RouterMock.queryRevertNoReasonHook.selector)
            )
        );

        return abi.decode(RawCallHelpers.unwrapRawCallResult(success, resultRaw), (uint256));
    }

    function queryRevertNoReasonHook() external pure returns (uint256) {
        revert();
    }
}
