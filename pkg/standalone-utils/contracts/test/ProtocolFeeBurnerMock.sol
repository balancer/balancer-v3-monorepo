// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";

import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

contract ProtocolFeeBurnerMock is IProtocolFeeBurner {
    using FixedPoint for uint256;

    uint256 private _tokenRatio = FixedPoint.ONE;

    /// @inheritdoc IProtocolFeeBurner
    function burn(
        IERC20 feeToken,
        uint256 exactFeeTokenAmountIn,
        IERC20 targetToken,
        uint256 minTargetTokenAmountOut,
        address recipient,
        uint256 deadline
    ) external {
        if (block.timestamp > deadline) {
            revert SwapDeadline();
        }

        // Simulate the swap by minting the same amount of target to the recipient.
        ERC20TestToken(address(targetToken)).mint(recipient, exactFeeTokenAmountIn);

        uint256 targetTokenAmount = exactFeeTokenAmountIn.mulDown(_tokenRatio);
        if (targetTokenAmount < minTargetTokenAmountOut) {
            revert AmountOutBelowMin(targetToken, targetTokenAmount, minTargetTokenAmountOut);
        }

        // Just emit the event, simulating the tokens being exchanged at 1-to-1.
        emit ProtocolFeeBurned(feeToken, exactFeeTokenAmountIn, targetToken, targetTokenAmount, recipient);
    }

    function setTokenRatio(uint256 ratio) external {
        _tokenRatio = ratio;
    }
}
