// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IProtocolFeeBurner {
    /**
     * @notice A protocol fee token has been "burned" (i.e., swapped for the desired target token).
     * @param pool The pool on which the fee was collected (used for event tracking)
     * @param feeToken The token in which the fee was originally collected
     * @param feeTokenAmount The number of feeTokens collected
     * @param targetToken The preferred token for fee collection (e.g., USDC)
     * @param targetTokenAmount The number of target tokens actually received
     * @param recipient The address where the target tokens were sent
     */
    event ProtocolFeeBurned(
        address indexed pool,
        IERC20 indexed feeToken,
        uint256 feeTokenAmount,
        IERC20 indexed targetToken,
        uint256 targetTokenAmount,
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
     * @param pool The pool the fees came from (only used for documentation in the event)
     * @param feeToken The feeToken collected from the pool
     * @param feeTokenAmount The number of fee tokens collected
     * @param targetToken The desired target token (token out of the swap)
     * @param minTargetTokenAmount The minimum amount out for the swap
     * @param recipient The recipient of the swap proceeds
     * @param deadline Deadline for the burn operation (i.e., swap), after which it will revert
     */
    function burn(
        address pool,
        IERC20 feeToken,
        uint256 feeTokenAmount,
        IERC20 targetToken,
        uint256 minTargetTokenAmount,
        address recipient,
        uint256 deadline
    ) external;
}