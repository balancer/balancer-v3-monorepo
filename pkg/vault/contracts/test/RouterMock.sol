// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { RevertCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/RevertCodec.sol";

import "../Router.sol";

contract RouterMock is Router {
    error MockErrorCode();

    constructor(IVault vault, IWETH weth, IPermit2 permit2) Router(vault, weth, permit2) {}

    function manualReentrancyInitializeHook() external nonReentrant {
        IRouter.InitializeHookParams memory hookParams;
        Router(payable(this)).initializeHook(hookParams);
    }

    function manualReentrancyAddLiquidityHook() external nonReentrant {
        AddLiquidityHookParams memory params;
        Router(payable(this)).addLiquidityHook(params);
    }

    function manualReentrancyRemoveLiquidityHook() external nonReentrant {
        RemoveLiquidityHookParams memory params;
        Router(payable(this)).removeLiquidityHook(params);
    }

    function manualReentrancyRemoveLiquidityRecoveryHook() external nonReentrant {
        Router(payable(this)).removeLiquidityRecoveryHook(address(0), address(0), 0);
    }

    function manualReentrancySwapSingleTokenHook() external nonReentrant {
        IRouter.SwapSingleTokenHookParams memory params;
        Router(payable(this)).swapSingleTokenHook(params);
    }

    function manualReentrancyAddLiquidityToBufferHook() external nonReentrant {
        Router(payable(this)).addLiquidityToBufferHook(IERC4626(address(0)), 0, 0, address(0));
    }

    function manualReentrancyRemoveLiquidityFromBufferHook() external nonReentrant {
        Router(payable(this)).removeLiquidityFromBufferHook(IERC4626(address(0)), 0, address(0));
    }

    function manualReentrancyQuerySwapHook() external nonReentrant {
        IRouter.SwapSingleTokenHookParams memory params;
        Router(payable(this)).querySwapHook(params);
    }

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
        try
            _vault.quoteAndRevert(
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
        {
            revert("Unexpected success");
        } catch (bytes memory result) {
            return abi.decode(RevertCodec.catchEncodedResult(result), (uint256));
        }
    }

    function querySpoof() external returns (uint256) {
        try _vault.quoteAndRevert(abi.encodeWithSelector(RouterMock.querySpoofHook.selector)) {
            revert("Unexpected success");
        } catch (bytes memory result) {
            return abi.decode(RevertCodec.catchEncodedResult(result), (uint256));
        }
    }

    function querySpoofHook() external pure {
        revert RevertCodec.Result(abi.encode(uint256(1234)));
    }

    function queryRevertErrorCode() external returns (uint256) {
        try _vault.quoteAndRevert(abi.encodeWithSelector(RouterMock.queryRevertErrorCodeHook.selector)) {
            revert("Unexpected success");
        } catch (bytes memory result) {
            return abi.decode(RevertCodec.catchEncodedResult(result), (uint256));
        }
    }

    function queryRevertErrorCodeHook() external pure {
        revert MockErrorCode();
    }

    function queryRevertLegacy() external returns (uint256) {
        try _vault.quoteAndRevert(abi.encodeWithSelector(RouterMock.queryRevertLegacyHook.selector)) {
            revert("Unexpected success");
        } catch (bytes memory result) {
            return abi.decode(RevertCodec.catchEncodedResult(result), (uint256));
        }
    }

    function queryRevertLegacyHook() external pure {
        revert("Legacy revert reason");
    }

    function queryRevertPanic() external returns (uint256) {
        try _vault.quoteAndRevert(abi.encodeWithSelector(RouterMock.queryRevertPanicHook.selector)) {
            revert("Unexpected success");
        } catch (bytes memory result) {
            return abi.decode(RevertCodec.catchEncodedResult(result), (uint256));
        }
    }

    function queryRevertPanicHook() external pure returns (uint256) {
        uint256 a = 10;
        uint256 b = 0;
        return a / b;
    }

    function queryRevertNoReason() external returns (uint256) {
        try _vault.quoteAndRevert(abi.encodeWithSelector(RouterMock.queryRevertNoReasonHook.selector)) {
            revert("Unexpected success");
        } catch (bytes memory result) {
            return abi.decode(RevertCodec.catchEncodedResult(result), (uint256));
        }
    }

    function queryRevertNoReasonHook() external pure returns (uint256) {
        revert();
    }
}
