// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IRouterSwap } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterSwap.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { RevertCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/RevertCodec.sol";

import { Router } from "../Router.sol";

string constant MOCK_ROUTER_VERSION = "Mock Router v1";

contract RouterMock is Router {
    using SafeCast for *;

    error MockErrorCode();

    constructor(IVault vault, IWETH weth, IPermit2 permit2) Router(vault, weth, permit2, MOCK_ROUTER_VERSION) {
        // solhint-disable-previous-line no-empty-blocks
    }

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
        Router(payable(this)).removeLiquidityRecoveryHook(address(0), address(0), 0, new uint256[](2));
    }

    function manualReentrancySwapSingleTokenHook() external nonReentrant {
        IRouterSwap.SwapSingleTokenHookParams memory params;
        Router(payable(this)).swapSingleTokenHook(params);
    }

    function manualReentrancyQuerySwapHook() external nonReentrant {
        IRouterSwap.SwapSingleTokenHookParams memory params;
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
                abi.encodeCall(
                    Router.querySwapHook,
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

    struct ManualAddRemoveLiquidityParams {
        address pool;
        address sender;
        uint256[] maxAmountsIn;
        uint256 minBptAmountOut;
    }

    function manualAddAndRemoveLiquidity(
        ManualAddRemoveLiquidityParams calldata params
    )
        external
        saveSender(msg.sender)
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, uint256 bptAmountIn, uint256[] memory amountsOut)
    {
        return
            abi.decode(
                _vault.unlock(abi.encodeCall(RouterMock.manualAddAndRemoveLiquidityHook, params)),
                (uint256[], uint256, uint256, uint256[])
            );
    }

    function manualAddAndRemoveLiquidityHook(
        ManualAddRemoveLiquidityParams calldata params
    )
        external
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, uint256 bptAmountIn, uint256[] memory amountsOut)
    {
        (amountsIn, bptAmountOut, ) = _vault.addLiquidity(
            AddLiquidityParams({
                pool: params.pool,
                to: params.sender,
                maxAmountsIn: params.maxAmountsIn,
                minBptAmountOut: params.minBptAmountOut,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        // maxAmountsIn length is checked against tokens length at the Vault.
        IERC20[] memory tokens = _vault.getPoolTokens(params.pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 amountIn = amountsIn[i];
            if (amountIn == 0) {
                continue;
            }

            // Any value over MAX_UINT128 would revert above in `addLiquidity`, so this SafeCast shouldn't be
            // necessary. Done out of an abundance of caution.
            _permit2.transferFrom(params.sender, address(_vault), amountIn.toUint160(), address(token));
            _vault.settle(token, amountIn);
        }

        (bptAmountIn, amountsOut, ) = _vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: params.pool,
                from: params.sender,
                maxBptAmountIn: IERC20(params.pool).balanceOf(params.sender),
                minAmountsOut: new uint256[](tokens.length),
                kind: RemoveLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 amountOut = amountsOut[i];
            if (amountOut == 0) {
                continue;
            }

            // Transfer the token to the sender (amountOut).
            _vault.sendTo(token, params.sender, amountOut);
        }
    }
}
