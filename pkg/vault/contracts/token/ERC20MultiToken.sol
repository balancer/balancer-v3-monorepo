// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { IERC20MultiTokenErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiTokenErrors.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";

import { BalancerPoolToken } from "../BalancerPoolToken.sol";

/**
 * @notice Store Token data and handle accounting for pool tokens in the Vault.
 * @dev The ERC20MultiToken is an ERC20-focused multi-token implementation that is fully compatible with the ERC20 API
 * on the token side. It also allows for the minting and burning of tokens on the multi-token side.
 */
abstract contract ERC20MultiToken is IERC20Errors, IERC20MultiTokenErrors {
    // Minimum total supply amount.
    uint256 internal constant _MINIMUM_TOTAL_SUPPLY = 1e6;

    /**
     * @notice Pool tokens are moved from one account (`from`) to another (`to`). Note that `value` may be zero.
     * @param pool The pool token being transferred
     * @param from The token source
     * @param to The token destination
     * @param value The number of tokens
     */
    event Transfer(address indexed pool, address indexed from, address indexed to, uint256 value);

    /**
     * @notice The allowance of a `spender` for an `owner` is set by a call to {approve}. `value` is the new allowance.
     * @param pool The pool token receiving the allowance
     * @param owner The token holder
     * @param spender The account being authorized to spend a given amount of the token
     * @param value The number of tokens spender is authorized to transfer from owner
     */
    event Approval(address indexed pool, address indexed owner, address indexed spender, uint256 value);

    // token -> (owner -> balance): Users' pool tokens balances
    mapping(address => mapping(address => uint256)) private _balances;

    // token -> (owner -> (spender -> allowance)): Users' allowances
    mapping(address => mapping(address => mapping(address => uint256))) private _allowances;

    // token -> total supply
    mapping(address => uint256) private _totalSupplyOf;

    function _totalSupply(address pool) internal view returns (uint256) {
        return _totalSupplyOf[pool];
    }

    function _balanceOf(address pool, address account) internal view returns (uint256) {
        return _balances[pool][account];
    }

    function _allowance(address pool, address owner, address spender) internal view returns (uint256) {
        // The Vault grants infinite allowance to all pool tokens (BPT)
        // Owner can spend anything without approval
        if (spender == address(this) || owner == spender) {
            return type(uint256).max;
        } else {
            return _allowances[pool][owner][spender];
        }
    }

    /**
     * @dev DO NOT CALL THIS METHOD!
     * Only `removeLiquidity` in the Vault may call this - in a query context - to allow burning tokens the caller
     * does not have.
     */
    function _queryModeBalanceIncrease(address pool, address to, uint256 amount) internal {
        // Enforce that this can only be called in a read-only, query context.
        if (EVMCallModeHelpers.isStaticCall() == false) {
            revert EVMCallModeHelpers.NotStaticCall();
        }

        // Increase `to` balance to ensure the burn function succeeds during query.
        _balances[address(pool)][to] += amount;
    }

    function _mint(address pool, address to, uint256 amount) internal {
        if (to == address(0)) {
            revert ERC20InvalidReceiver(to);
        }

        uint256 newTotalSupply = _totalSupplyOf[pool] + amount;
        unchecked {
            // Overflow is not possible. balance + amount is at most totalSupply + amount, which is checked above.
            _balances[pool][to] += amount;
        }

        _ensureMinimumTotalSupply(newTotalSupply);

        _totalSupplyOf[pool] = newTotalSupply;

        emit Transfer(pool, address(0), to, amount);

        // We also emit the "transfer" event on the pool token to ensure full compliance with the ERC20 standard.
        BalancerPoolToken(pool).emitTransfer(address(0), to, amount);
    }

    function _ensureMinimumTotalSupply(uint256 newTotalSupply) internal pure {
        if (newTotalSupply < _MINIMUM_TOTAL_SUPPLY) {
            revert TotalSupplyTooLow(newTotalSupply, _MINIMUM_TOTAL_SUPPLY);
        }
    }

    function _mintMinimumSupplyReserve(address pool) internal {
        _totalSupplyOf[pool] += _MINIMUM_TOTAL_SUPPLY;
        unchecked {
            // Overflow is not possible. balance + amount is at most totalSupply + amount, which is checked above.
            _balances[pool][address(0)] += _MINIMUM_TOTAL_SUPPLY;
        }
        emit Transfer(pool, address(0), address(0), _MINIMUM_TOTAL_SUPPLY);

        // We also emit the "transfer" event on the pool token to ensure full compliance with the ERC20 standard.
        BalancerPoolToken(pool).emitTransfer(address(0), address(0), _MINIMUM_TOTAL_SUPPLY);
    }

    function _burn(address pool, address from, uint256 amount) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(from);
        }

        uint256 accountBalance = _balances[pool][from];
        if (amount > accountBalance) {
            revert ERC20InsufficientBalance(from, accountBalance, amount);
        }

        unchecked {
            _balances[pool][from] = accountBalance - amount;
        }
        uint256 newTotalSupply = _totalSupplyOf[pool] - amount;

        _ensureMinimumTotalSupply(newTotalSupply);

        _totalSupplyOf[pool] = newTotalSupply;

        emit Transfer(pool, from, address(0), amount);

        // We also emit the "transfer" event on the pool token to ensure full compliance with the ERC20 standard.
        BalancerPoolToken(pool).emitTransfer(from, address(0), amount);
    }

    function _transfer(address pool, address from, address to, uint256 amount) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(from);
        }

        if (to == address(0)) {
            revert ERC20InvalidReceiver(to);
        }

        uint256 fromBalance = _balances[pool][from];
        if (amount > fromBalance) {
            revert ERC20InsufficientBalance(from, fromBalance, amount);
        }

        unchecked {
            _balances[pool][from] = fromBalance - amount;
            // Overflow is not possible. The sum of all balances is capped by totalSupply, and that sum is preserved by
            // decrementing then incrementing.
            _balances[pool][to] += amount;
        }

        emit Transfer(pool, from, to, amount);

        // We also emit the "transfer" event on the pool token to ensure full compliance with the ERC20 standard.
        BalancerPoolToken(pool).emitTransfer(from, to, amount);
    }

    function _approve(address pool, address owner, address spender, uint256 amount) internal {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(owner);
        }

        if (spender == address(0)) {
            revert ERC20InvalidSpender(spender);
        }

        _allowances[pool][owner][spender] = amount;

        emit Approval(pool, owner, spender, amount);
        // We also emit the "approve" event on the pool token to ensure full compliance with the ERC20 standard.
        BalancerPoolToken(pool).emitApproval(owner, spender, amount);
    }

    function _spendAllowance(address pool, address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowance(pool, owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (amount > currentAllowance) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, amount);
            }

            unchecked {
                _approve(pool, owner, spender, currentAllowance - amount);
            }
        }
    }
}
