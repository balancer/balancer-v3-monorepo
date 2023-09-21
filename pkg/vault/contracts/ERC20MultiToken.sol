// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IERC20Errors } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/tokens/IERC20Errors.sol";

import { ERC20PoolToken } from "./ERC20PoolToken.sol";

/**
 * @notice Store Token data and handle accounting for all tokens in the Vault.
 * @dev The ERC20MultiToken is an ERC20-focused multi-token implementation that is fully compatible
 * with the ERC20 API on the token side. It also allows for the minting and burning of tokens on the multi-token side.
 */
abstract contract ERC20MultiToken is IERC20Errors {
    using Address for address;

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed token, address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed token, address indexed owner, address indexed spender, uint256 value);

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

        emit Transfer(token, address(0), to, amount);

        // We use a low-level call here because only `ERC20PoolToken` tokens implement `emitTransfer`.
        // Standard tokens, such as USDC, do not implement `emitTransfer`, so this call would fail.
        // While this is expected behavior and not an issue in itself, malicious ERC20 contracts
        // might exploit it for reentrancy. Hence, caution is needed.
        try ERC20PoolToken(token).emitTransfer(address(0), to, amount) {} catch {
            // solhint-disable-previous-line no-empty-blocks
        }
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

        emit Transfer(token, from, address(0), amount);

        // We use a low-level call here because only `ERC20PoolToken` tokens implement `emitTransfer`.
        // Standard tokens, such as USDC, do not implement `emitTransfer`, so this call would fail.
        // While this is expected behavior and not an issue in itself, malicious ERC20 contracts
        // might exploit it for reentrancy. Hence, caution is needed.
        try ERC20PoolToken(token).emitTransfer(from, address(0), amount) {} catch {
            // solhint-disable-previous-line no-empty-blocks
        }
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

        emit Transfer(token, from, to, amount);

        // We use a low-level call here because only `ERC20PoolToken` tokens implement `emitTransfer`.
        // Standard tokens, such as USDC, do not implement `emitTransfer`, so this call would fail.
        // While this is expected behavior and not an issue in itself, malicious ERC20 contracts
        // might exploit it for reentrancy. Hence, caution is needed.
        try ERC20PoolToken(token).emitTransfer(from, to, amount) {} catch {
            // solhint-disable-previous-line no-empty-blocks
        }
    }

    function _approve(address token, address owner, address spender, uint256 amount) internal {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(owner);
        }

        if (spender == address(0)) {
            revert ERC20InvalidSpender(spender);
        }

        _allowances[token][owner][spender] = amount;

        emit Approval(token, owner, spender, amount);

        // We use a low-level call here because only `ERC20PoolToken` tokens implement `emitApprove`.
        // Standard tokens, such as USDC, do not implement `emitApprove`, so this call would fail.
        // While this is expected behavior and not an issue in itself, malicious ERC20 contracts
        // might exploit it for reentrancy. Hence, caution is needed.
        try ERC20PoolToken(token).emitApprove(owner, spender, amount) {} catch {
            // solhint-disable-previous-line no-empty-blocks
        }
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
