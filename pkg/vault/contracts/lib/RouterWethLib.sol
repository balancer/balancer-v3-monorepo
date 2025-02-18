// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { StorageSlotExtension } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

library RouterWethLib {
    using Address for address payable;
    using StorageSlotExtension for *;
    using SafeERC20 for IWETH;

    /// @notice The amount of ETH paid is insufficient to complete this operation.
    error InsufficientEth();

    function wrapEthAndSettle(IWETH weth, IVault vault, uint256 amountToSettle) internal {
        if (address(this).balance < amountToSettle) {
            revert InsufficientEth();
        }

        // wrap amountIn to WETH.
        weth.deposit{ value: amountToSettle }();
        // send WETH to Vault.
        weth.safeTransfer(address(vault), amountToSettle);
        // update Vault accounting.
        vault.settle(weth, amountToSettle);
    }

    function unwrapWethAndTransferToSender(IWETH weth, IVault vault, address sender, uint256 amountToSend) internal {
        // Receive the WETH amountOut.
        vault.sendTo(weth, address(this), amountToSend);
        // Withdraw WETH to ETH.
        weth.withdraw(amountToSend);
        // Send ETH to sender.
        payable(sender).sendValue(amountToSend);
    }
}
