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

    /**
     * @dev Returns excess ETH back to the contract caller. Checks for sufficient ETH balance are made right before
     * each deposit, ensuring it will revert with a friendly custom error. If there is any balance remaining when
     * `_returnEth` is called, return it to the sender.
     *
     * Because the caller might not know exactly how much ETH a Vault action will require, they may send extra.
     * Note that this excess value is returned *to the contract caller* (msg.sender). If caller and e.g. swap sender
     * are not the same (because the caller is a relayer for the sender), then it is up to the caller to manage this
     * returned ETH.
     */
    function returnEth(IWETH, address sender) internal {
        uint256 excess = address(this).balance;
        if (excess == 0) {
            return;
        }

        payable(sender).sendValue(excess);
    }

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
