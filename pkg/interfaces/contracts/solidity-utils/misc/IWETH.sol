// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Interface for WETH9.
 * See https://github.com/gnosis/canonical-weth/blob/0dd1ea3e295eef916d0c6223ec63141137d22d67/contracts/WETH9.sol
 */
interface IWETH is IERC20 {
    /**
     * @notice "wrap" native ETH to WETH.
     * @dev The amount is msg.value.
     */
    function deposit() external payable;

    /**
     * @notice "unwrap" WETH to native ETH.
     * @param amount The amount to withdraw
     */
    function withdraw(uint256 amount) external;
}
