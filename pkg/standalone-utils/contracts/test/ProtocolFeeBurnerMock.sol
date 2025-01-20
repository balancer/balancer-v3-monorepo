// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeSweeper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeSweeper.sol";
import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";

import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

contract ProtocolFeeBurnerMock is IProtocolFeeBurner {
    using SafeERC20 for IERC20;

    /// @inheritdoc IProtocolFeeBurner
    function burn(
        address pool,
        IERC20 feeToken,
        uint256 feeTokenAmount,
        IERC20 targetToken,
        address recipient
    ) external {
        // Simulate the swap by minting the same amount of target to the recipient.
        ERC20TestToken(address(targetToken)).mint(recipient, feeTokenAmount);

        // Just emit the event, simulating the tokens being exchanged at 1-to-1.
        emit ProtocolFeeBurned(pool, feeToken, feeTokenAmount, targetToken, feeTokenAmount, recipient);
    }
}
