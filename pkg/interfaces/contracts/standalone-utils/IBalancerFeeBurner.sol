// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IProtocolFeeBurner } from "./IProtocolFeeBurner.sol";

interface IBalancerFeeBurner is IProtocolFeeBurner {
    /**
     * @notice Steps for the burn path.
     * @param pool The pool for the swap
     * @param tokenOut The `tokenOut` of the swap operation
     */
    struct SwapPathStep {
        address pool;
        IERC20 tokenOut;
    }

    /**
     * @notice Data for the burn hook.
     * @param pool The pool the fees came from (only used for documentation in the event)
     * @param sender The sender of the call. In most cases, this is the sweeper.
     * @param feeToken The token collected from the pool
     * @param feeTokenAmount The number of fee tokens collected
     * @param targetToken The desired target token (`tokenOut` of the swap)
     * @param minAmountOut The minimum `amountOut` for the swap
     * @param recipient The recipient of the swap proceeds
     * @param deadline Deadline for the burn operation (i.e., swap), after which it will revert
     */
    struct BurnHookParams {
        address pool;
        address sender;
        IERC20 feeToken;
        uint256 feeTokenAmount;
        IERC20 targetToken;
        uint256 minAmountOut;
        address recipient;
        uint256 deadline;
    }

    /// @notice Burn path not set for the fee token.
    error BurnPathDoesNotExist();

    /// @notice The last token in the path is not the same as the target token.
    error TargetTokenOutMismatch();

    /**
     * @notice Set the burn path for a fee token.
     * @dev This is the sequence of swaps required to convert the `feeToken` to the `targetToken`.
     * This is a permissioned function.
     *
     * @param feeToken The fee token to set the path for
     * @param steps The steps in the burn path
     */
    function setBurnPath(IERC20 feeToken, SwapPathStep[] calldata steps) external;

    /**
     * @notice Get the burn path for a fee token.
     * @param feeToken The fee token to get the path for
     * @return steps The steps in the burn path
     */
    function getBurnPath(IERC20 feeToken) external view returns (SwapPathStep[] memory steps);
}
