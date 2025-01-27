// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IProtocolFeeBurner {
    /**
     * @notice A protocol fee token has been "burned" (i.e., swapped for the desired target token).
     * @param feeToken The token in which the fee was originally collected
     * @param exactFeeTokenAmountIn The number of feeTokens collected
     * @param targetToken The preferred token for fee collection (e.g., USDC)
     * @param targetTokenAmountOut The number of target tokens actually received
     * @param recipient The address where the target tokens were sent
     */
    event ProtocolFeeBurned(
        IERC20 indexed feeToken,
        uint256 exactFeeTokenAmountIn,
        IERC20 indexed targetToken,
        uint256 targetTokenAmountOut,
        address recipient
    );

    /**
     * @notice The actual amount out is below the minimum limit specified for the operation.
     * @param tokenOut The outgoing token
     * @param amountOut The total BPT amount out
     * @param minAmountOut The amount of the limit that has been exceeded
     */
    error AmountOutBelowMin(IERC20 tokenOut, uint256 amountOut, uint256 minAmountOut);

    /// @notice The swap transaction was not validated before the specified deadline timestamp.
    error SwapDeadline();

    /**
     * @notice Swap an exact amount of `feeToken` for the `targetToken`, and send proceeds to the `recipient`.
     * @dev Assumes the sweeper has transferred the tokens to the burner prior to the call.
     * @param feeToken The feeToken collected from the pool
     * @param exactFeeTokenAmountIn The number of fee tokens collected
     * @param targetToken The desired target token (token out of the swap)
     * @param minTargetTokenAmountOut The minimum amount out for the swap
     * @param recipient The recipient of the swap proceeds
     * @param deadline Deadline for the burn operation (i.e., swap), after which it will revert
     */
    function burn(
        IERC20 feeToken,
        uint256 exactFeeTokenAmountIn,
        IERC20 targetToken,
        uint256 minTargetTokenAmountOut,
        address recipient,
        uint256 deadline
    ) external;
}
