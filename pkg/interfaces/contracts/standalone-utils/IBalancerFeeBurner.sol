// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IProtocolFeeBurner } from "./IProtocolFeeBurner.sol";

interface IBalancerFeeBurner is IProtocolFeeBurner {
    struct SwapPathStep {
        address pool;
        IERC20 tokenOut;
    }

    struct BurnHookParams {
        address pool;
        IERC20 feeToken;
        uint256 feeTokenAmount;
        IERC20 targetToken;
        uint256 minAmountOut;
        address recipient;
        uint256 deadline;
    }

    error BurnPathNotExists(IERC20 feeToken);

    function setBurnPath(IERC20 feeToken, SwapPathStep[] calldata steps) external;

    function getBurnPath(IERC20 feeToken) external view returns (SwapPathStep[] memory steps);

    function burnHook(BurnHookParams calldata params) external;
}
