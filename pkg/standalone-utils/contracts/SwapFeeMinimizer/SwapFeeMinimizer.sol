// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

interface ISwapFeeMinimizerFactory {
    function getCurrentPool() external view returns (address);
}

/**
 * @notice Helper contract that minimizes swap fees for the contract `owner` when swapping a specific
 *         `outputToken` from a specific pool.
 * @dev Temporarily reduces swap fees to a minimal level during swap execution for owner-only swaps
 */
contract SwapFeeMinimizer is Ownable2Step, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    IRouter private immutable _router;
    IVault private immutable _vault;
    IPermit2 private immutable _permit2;
    address private immutable _pool;
    IERC20 private immutable _outputToken;
    uint256 private immutable _minimalSwapFee;

    error FeeValidationFailed();
    error InvalidOutputToken(IERC20 expected, IERC20 actual);
    error InvalidPool();
    error RouterCallFailed();

    modifier withSwapMinimized() {
        uint256 originalFee = _vault.getStaticSwapFeePercentage(_pool);
        _vault.setStaticSwapFeePercentage(_pool, _minimalSwapFee);
        _;
        _vault.setStaticSwapFeePercentage(_pool, originalFee);
    }

    modifier onlyOutputTokenFromPool(IERC20 tokenOut, address poolAddress) {
        if (tokenOut != _outputToken) {
            revert InvalidOutputToken(_outputToken, tokenOut);
        }
        if (poolAddress != _pool) {
            revert InvalidPool();
        }
        _;
    }

    constructor(
        IRouter router,
        IVault vault,
        IPermit2 permit2,
        IERC20[] memory inputTokens,
        IERC20 outputToken,
        uint256 minimalSwapFeeAmount,
        address initialOwner
    ) Ownable(initialOwner) {
        _router = router;
        _vault = vault;
        _permit2 = permit2;
        _outputToken = outputToken;
        _minimalSwapFee = minimalSwapFeeAmount;

        // Get the just-deployed pool address from the factory since it cannot be passed as a constructor arg
        address poolAddress = ISwapFeeMinimizerFactory(msg.sender).getCurrentPool();
        _pool = poolAddress;

        // Max approve all possible input tokens for the pool

        // Note: we don't unlock the output token since any attempt to swap with
        // that token as an input token will revert. This contract itself sets permit2 ERC20
        // allowances to max and then each swap approves either the exact amount being swapped
        // of the max allowable input amount for that swap.
        for (uint256 i = 0; i < inputTokens.length; i++) {
            inputTokens[i].forceApprove(address(_permit2), type(uint256).max);
        }

        // Validate that fee-setting permissions and `minimalSwapFeeAmount` are valid

        // Note: using two _setAndValidateFee calls here since the weighted
        // pool factory itself is an argument to the minimizer factory and,
        // though unlikely, it is possible that the max/min fees in the pool
        // could change
        uint256 originalFee = _vault.getStaticSwapFeePercentage(poolAddress);
        _setAndValidateFee(poolAddress, minimalSwapFeeAmount);
        _setAndValidateFee(poolAddress, originalFee);
    }

    function _setAndValidateFee(address poolAddress, uint256 feeAmount) internal {
        _vault.setStaticSwapFeePercentage(poolAddress, feeAmount);
        if (_vault.getStaticSwapFeePercentage(poolAddress) != feeAmount) {
            revert FeeValidationFailed();
        }
    }

    function _pullTokensFromOwnerAndApprove(IERC20 tokenIn, uint256 amount, uint256 deadline) internal {
        tokenIn.safeTransferFrom(msg.sender, address(this), amount);
        // using the swap deadline for the permit2 deadline is safe since
        // the swap deadline gets checked before transferFrom is called
        _permit2.approve(address(tokenIn), address(_router), uint160(amount), uint48(deadline));
    }

    /**
     * @notice Swap exact amount of input token for minimum amount of output token with minimized fees
     * @dev External function encodes router calldata and calls internal function to avoid stack-too-deep errors.
     *      The internal function contains all security modifiers and business logic.
     */
    function swapSingleTokenExactIn(
        address poolAddress,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256) {
        bytes memory routerCalldata = abi.encodeWithSelector(
            IRouter.swapSingleTokenExactIn.selector,
            poolAddress,
            tokenIn,
            tokenOut,
            exactAmountIn,
            minAmountOut,
            deadline,
            wethIsEth,
            userData
        );

        return _executeSwapExactIn(routerCalldata, tokenIn, tokenOut, poolAddress, exactAmountIn, deadline);
    }

    function _executeSwapExactIn(
        bytes memory routerCalldata,
        IERC20 tokenIn,
        IERC20 tokenOut,
        address poolAddress,
        uint256 exactAmountIn,
        uint256 deadline
    )
        internal
        onlyOwner
        onlyOutputTokenFromPool(tokenOut, poolAddress)
        withSwapMinimized
        nonReentrant
        returns (uint256)
    {
        _pullTokensFromOwnerAndApprove(tokenIn, exactAmountIn, deadline);

        (bool success, bytes memory result) = address(_router).call{ value: msg.value }(routerCalldata);
        if (!success) {
            revert RouterCallFailed();
        }
        uint256 amountOut = abi.decode(result, (uint256));

        tokenOut.safeTransfer(msg.sender, amountOut);
        return amountOut;
    }

    /**
     * @notice Swap maximum amount of input token for exact amount of output token with minimized fees
     * @dev External function encodes router calldata and calls internal function to avoid stack-too-deep errors.
     *      The internal function contains all security modifiers and business logic.
     */
    function swapSingleTokenExactOut(
        address poolAddress,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256) {
        bytes memory routerCalldata = abi.encodeWithSelector(
            IRouter.swapSingleTokenExactOut.selector,
            poolAddress,
            tokenIn,
            tokenOut,
            exactAmountOut,
            maxAmountIn,
            deadline,
            wethIsEth,
            userData
        );

        return
            _executeSwapExactOut(routerCalldata, tokenIn, tokenOut, poolAddress, exactAmountOut, maxAmountIn, deadline);
    }

    function _executeSwapExactOut(
        bytes memory routerCalldata,
        IERC20 tokenIn,
        IERC20 tokenOut,
        address poolAddress,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline
    )
        internal
        onlyOwner
        onlyOutputTokenFromPool(tokenOut, poolAddress)
        withSwapMinimized
        nonReentrant
        returns (uint256)
    {
        _pullTokensFromOwnerAndApprove(tokenIn, maxAmountIn, deadline);

        (bool success, bytes memory result) = address(_router).call{ value: msg.value }(routerCalldata);
        if (!success) {
            revert RouterCallFailed();
        }
        uint256 amountIn = abi.decode(result, (uint256));

        tokenOut.safeTransfer(msg.sender, exactAmountOut);

        // Return leftover input tokens if any (`amountIn` determined at execution time)
        if (amountIn < maxAmountIn) {
            tokenIn.safeTransfer(msg.sender, maxAmountIn - amountIn);
        }

        return amountIn;
    }

    function setSwapFeePercentage(uint256 swapFeePercentage) external onlyOwner {
        _vault.setStaticSwapFeePercentage(_pool, swapFeePercentage);
    }

    function getRouter() external view returns (IRouter) {
        return _router;
    }

    function getVault() external view returns (IVault) {
        return _vault;
    }

    function getPool() external view returns (address) {
        return _pool;
    }

    function getOutputToken() external view returns (IERC20) {
        return _outputToken;
    }

    function getMinimalSwapFee() external view returns (uint256) {
        return _minimalSwapFee;
    }
}
