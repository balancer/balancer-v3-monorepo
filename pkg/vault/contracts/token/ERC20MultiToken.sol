// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiToken.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";

import { BalancerPoolToken } from "../BalancerPoolToken.sol";

/**
 * @notice Store Token data and handle accounting for pool tokens in the Vault.
 * @dev The ERC20MultiToken is an ERC20-focused multi-token implementation that is fully compatible
 * with the ERC20 API on the token side. It also allows for the minting and burning of tokens on the multi-token side.
 */
abstract contract ERC20MultiToken is IERC20Errors, IERC20MultiToken {
    using Address for address;

    // Minimum total supply amount.
    uint256 internal constant _MINIMUM_TOTAL_SUPPLY = 1e6;

    /**
     * @notice Pool tokens are moved from one account (`from`) to another (`to`). Note that `value` may be zero.
     * @param token The token being transferred
     * @param from The token source
     * @param to The token destination
     * @param value The number of tokens
     */
    event Transfer(address indexed token, address indexed from, address indexed to, uint256 value);

    /**
     * @notice The allowance of a `spender` for an `owner` is set by a call to {approve}. `value` is the new allowance.
     * @param token The token receiving the allowance
     * @param owner The token holder
     * @param spender The account being authorized to spend a given amount of the token
     * @param value The number of tokens spender is authorized to transfer from owner
     */
    event Approval(address indexed token, address indexed owner, address indexed spender, uint256 value);

    // token -> (owner -> balance): Users' pool tokens balances
    mapping(address => mapping(address => uint256)) private _balances;

    // token -> (owner -> (spender -> allowance)): Users' allowances
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
        // The Vault grants infinite allowance to all pool tokens (BPT)
        if (spender == address(this)) {
            return type(uint256).max;
        } else {
            return _allowances[token][owner][spender];
        }
    }

    /**
     * @dev DO NOT CALL THIS METHOD!
     * Only `removeLiquidity` in the Vault may call this - in a query context - to allow burning tokens the caller
     * does not have.
     */
    function _queryModeBalanceIncrease(address token, address to, uint256 amount) internal {
        // Enforce that this can only be called in a read-only, query context.
        if (!EVMCallModeHelpers.isStaticCall()) {
            revert EVMCallModeHelpers.NotStaticCall();
        }

        // Increase `to` balance to ensure the burn function succeeds during query.
        _balances[address(token)][to] += amount;
    }

    function _mint(address token, address to, uint256 amount) internal {
        if (to == address(0)) {
            revert ERC20InvalidReceiver(to);
        }

        uint256 newTotalSupply = _totalSupplyOf[token] + amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[token][to] += amount;
        }

        if (newTotalSupply < _MINIMUM_TOTAL_SUPPLY) {
            revert TotalSupplyTooLow(newTotalSupply, _MINIMUM_TOTAL_SUPPLY);
        }
        _totalSupplyOf[token] = newTotalSupply;

        emit Transfer(token, address(0), to, amount);

        // We also invoke the "transfer" event on the pool token to ensure full compliance with ERC20 standards.
        BalancerPoolToken(token).emitTransfer(address(0), to, amount);
    }

    function _mintMinimumSupplyReserve(address token) internal {
        _totalSupplyOf[token] += _MINIMUM_TOTAL_SUPPLY;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[token][address(0)] += _MINIMUM_TOTAL_SUPPLY;
        }
        emit Transfer(token, address(0), address(0), _MINIMUM_TOTAL_SUPPLY);

        // We also invoke the "transfer" event on the pool token to ensure full compliance with ERC20 standards.
        BalancerPoolToken(token).emitTransfer(address(0), address(0), _MINIMUM_TOTAL_SUPPLY);
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
        }
        uint256 newTotalSupply = _totalSupplyOf[token] - amount;

        if (newTotalSupply < _MINIMUM_TOTAL_SUPPLY) {
            revert TotalSupplyTooLow(newTotalSupply, _MINIMUM_TOTAL_SUPPLY);
        }

        _totalSupplyOf[token] = newTotalSupply;

        emit Transfer(token, from, address(0), amount);

        // We also invoke the "transfer" event on the pool token to ensure full compliance with ERC20 standards.
        BalancerPoolToken(token).emitTransfer(from, address(0), amount);
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

        // We also invoke the "transfer" event on the pool token to ensure full compliance with ERC20 standards.
        BalancerPoolToken(token).emitTransfer(from, to, amount);
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
        // We also invoke the "approve" event on the pool token to ensure full compliance with ERC20 standards.
        BalancerPoolToken(token).emitApproval(owner, spender, amount);
    }

    function _spendAllowance(address token, address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowance(token, owner, spender);
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
