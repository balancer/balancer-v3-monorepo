// SPDX-License-Identifier: GPL-3.0-or-later

// This flash loan provider was based on the Aave protocol's open source
// implementation and terminology and interfaces are intentionally kept
// similar

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IFlashLoanRecipient.sol";

import "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/SafeERC20.sol";

import "./Fees.sol";

/**
 * @dev Handles Flash Loans through the Vault. Calls the `receiveFlashLoan` hook on the flash loan recipient
 * contract, which implements the `IFlashLoanRecipient` interface.
 */
abstract contract FlashLoans is Fees, ReentrancyGuard, TemporarilyPausable {
    using SafeERC20 for IERC20;

    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external override nonReentrant whenNotPaused {
        InputHelpers.ensureInputLengthMatch(tokens.length, amounts.length);

        uint256[] memory feeAmounts = new uint256[](tokens.length);
        uint256[] memory preLoanBalances = new uint256[](tokens.length);

        // Used to ensure `tokens` is sorted in ascending order, which ensures token uniqueness.
        IERC20 previousToken = IERC20(0);

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 amount = amounts[i];

            _require(token > previousToken, token == IERC20(0) ? Errors.ZERO_TOKEN : Errors.UNSORTED_TOKENS);
            previousToken = token;

            preLoanBalances[i] = token.balanceOf(address(this));
            feeAmounts[i] = _calculateFlashLoanFeeAmount(amount);

            _require(preLoanBalances[i] >= amount, Errors.INSUFFICIENT_FLASH_LOAN_BALANCE);
            token.safeTransfer(address(recipient), amount);
        }

        recipient.receiveFlashLoan(tokens, amounts, feeAmounts, userData);

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 preLoanBalance = preLoanBalances[i];

            // Checking for loan repayment first (without accounting for fees) makes for simpler debugging, and results
            // in more accurate revert reasons if the flash loan protocol fee percentage is zero.
            uint256 postLoanBalance = token.balanceOf(address(this));
            _require(postLoanBalance >= preLoanBalance, Errors.INVALID_POST_LOAN_BALANCE);

            // No need for checked arithmetic since we know the loan was fully repaid.
            uint256 receivedFeeAmount = postLoanBalance - preLoanBalance;
            _require(receivedFeeAmount >= feeAmounts[i], Errors.INSUFFICIENT_FLASH_LOAN_FEE_AMOUNT);

            _payFeeAmount(token, receivedFeeAmount);
            emit FlashLoan(recipient, token, amounts[i], receivedFeeAmount);
        }
    }
}
