// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICowRouter {
    struct CowSwapExactInParams {
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 exactAmountIn;
        uint256 minAmountOut;
        uint256 deadline;
    }

    struct CowSwapExactOutParams {
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 exactAmountOut;
        uint256 maxAmountIn;
        uint256 deadline;
    }

    event CoWSwappingAndDonation(
        address pool,
        uint256 amountInSwap,
        IERC20 tokenInSwap,
        uint256 amnountOutSwap,
        IERC20 tokenOutSwap,
        IERC20[] surplusTokens,
        uint256[] donatedSurplus,
        uint256[] feeAmountCollectedByProtocol,
        bytes userData
    );

    event CoWDonation(
        address pool,
        IERC20[] surplusTokens,
        uint256[] donatedSurplus,
        uint256[] feeAmountCollectedByProtocol,
        bytes userData
    );

    function swapExactInAndDonateSurplus(
        address pool,
        CowSwapExactInParams memory params,
        uint256[] memory surplusToDonate,
        bytes memory userData
    ) external returns (uint256 exactAmountOut);

    function swapExactOutAndDonateSurplus(
        address pool,
        CowSwapExactOutParams memory params,
        uint256[] memory surplusToDonate,
        bytes memory userData
    ) external returns (uint256 exactAmountIn);

    function donate(address pool, uint256[] memory amountsIn, bytes memory userData) external;

    function getProtocolFeePercentage() external view returns (uint256 protocolFeePercentage);

    function getProtocolFees(IERC20 token) external view returns (uint256 fees);

    function setProtocolFeePercentage(uint256 newProtocolFeePercentage) external;
}
