// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { Asset } from "../solidity-utils/misc/Asset.sol";

import { IVault } from "./IVault.sol";
import { IAuthorizer } from "./IAuthorizer.sol";
import { IBasePool } from "./IBasePool.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IProtocolFeesCollector {
    event SwapFeePercentageChanged(uint256 newSwapFeePercentage);

    function withdrawCollectedFees(IERC20[] calldata tokens, uint256[] calldata amounts, address recipient) external;

    function setSwapFeePercentage(uint256 newSwapFeePercentage) external;

    function getSwapFeePercentage() external view returns (uint256);

    function getCollectedFeeAmounts(IERC20[] memory tokens) external view returns (uint256[] memory feeAmounts);

    function getAuthorizer() external view returns (IAuthorizer);

    function vault() external view returns (IVault);
}
