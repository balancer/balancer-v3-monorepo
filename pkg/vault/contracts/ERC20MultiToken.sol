// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20Errors } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/tokens/IERC20Errors.sol";

import { ERC20PoolToken } from "./ERC20PoolToken.sol";

/**
 * @notice Store Token data and handle accounting for all tokens in the Vault.
 * @dev The ERC20MultiToken is an ERC20-focused multi-token implementation that is fully compatible
 * with the ERC20 API on the token side. It also allows for the minting and burning of tokens on the multi-token side.
 */
abstract contract ERC20MultiToken is IERC20Errors {
    // token -> (owner -> balance): Users' balances
    mapping(address => mapping(address => uint256)) private _balances;

    // token -> (owner -> (spender -> allowance))
    mapping(address => mapping(address => mapping(address => uint256))) private _allowances;

    // token -> total supply
    mapping(address => uint256) private _totalSupplyOf;

    function _totalSupply(address token) internal view returns (uint256) {
        return _totalSupplyOf[token];
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        return _balances[token][account];
    }

    function _allowance(address token, address owner, address spender) internal view returns (uint256) {
        return _allowances[token][owner][spender];
    }

    function _mint(address token, address to, uint256 amount) internal {
        if (to == address(0)) {
            revert ERC20InvalidReceiver(to);
        }

        _totalSupplyOf[token] += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[token][to] += amount;
        }

        ERC20PoolToken(token).emitTransfer(address(0), to, amount);
    }

    function _burn(address token, address from, uint256 amount) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(from);
        }

        uint256 accountBalance = _balances[token][from];
        if (amount > accountBalance) {
            revert ERC20InsufficientBalance(from, accountBalance, amount);
        }

        unchecked {
            _balances[token][from] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupplyOf[token] -= amount;
        }

        ERC20PoolToken(token).emitTransfer(from, address(0), amount);
    }

    function _transfer(address token, address from, address to, uint256 amount) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(from);
        }

        if (to == address(0)) {
            revert ERC20InvalidReceiver(to);
        }

        uint256 fromBalance = _balances[token][from];
        if (amount > fromBalance) {
            revert ERC20InsufficientBalance(from, fromBalance, amount);
        }

        unchecked {
            _balances[token][from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[token][to] += amount;
        }

        ERC20PoolToken(token).emitTransfer(from, to, amount);
    }

    function _approve(address token, address owner, address spender, uint256 amount) internal {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(owner);
        }

        if (spender == address(0)) {
            revert ERC20InvalidSpender(spender);
        }

        _allowances[token][owner][spender] = amount;
        ERC20PoolToken(token).emitApprove(owner, spender, amount);
    }

    function _spendAllowance(address token, address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[token][owner][spender];
        if (currentAllowance != type(uint256).max) {
            if (amount > currentAllowance) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, amount);
            }

            unchecked {
                _approve(token, owner, spender, currentAllowance - amount);
            }
        }
    }
}
