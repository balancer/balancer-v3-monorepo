// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IProtocolFeeBurner {
    event ProtocolFeeBurned(
        address indexed pool,
        IERC20 indexed feeToken,
        uint256 feeTokenAmount,
        IERC20 indexed targetToken,
        uint256 targetTokenAmount,
        address recipient
    );

    /**
     * @notice Swap an exact amount of `feeToken` for the `targetToken`, and send proceeds to the `recipient`.
     * @dev Assumes the sweeper has transferred the tokens to the burner prior to the call.
     * @param pool The pool the fees came from (only used for documentation in the event)
     * @param feeToken The feeToken collected from the pool
     * @param feeTokenAmount The number of fee tokens collected
     * @param targetToken The desired target token (token out of the swap)
     * @param recipient The recipient of the swap proceeds
     */
    function burn(
        address pool,
        IERC20 feeToken,
        uint256 feeTokenAmount,
        IERC20 targetToken,
        address recipient
    ) external;
}
