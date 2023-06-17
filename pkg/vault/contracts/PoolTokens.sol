// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./PoolRegistry.sol";
import "./BalancerPoolToken.sol";

abstract contract PoolTokens is PoolRegistry {
    // Pool -> (holder -> balance): Users' BPT balances
    mapping(address => mapping(address => uint256)) private _accountBPTBalances;

    // Pool -> (owner -> (spender -> allowance))
    mapping(address => mapping(address => mapping(address => uint256))) private _allowances;

    // Pool -> total supply (BPT)
    mapping(address => uint256) private _totalSupply;

    function totalSupply(address poolToken) public view override returns (uint256) {
        return _totalSupply[poolToken];
    }

    function balanceOf(address poolToken, address account) public view returns (uint256) {
        return _accountBPTBalances[poolToken][account];
    }

    function allowance(address poolToken, address owner, address spender) public view returns (uint256) {
        return _allowances[poolToken][owner][spender];
    }

    function transfer(
        address poolToken,
        address owner,
        address to,
        uint256 amount
    ) public withRegisteredPool(poolToken) returns (bool) {
        _transfer(poolToken, owner, to, amount);
        return true;
    }

    function approve(
        address poolToken,
        address sender,
        address spender,
        uint256 amount
    ) public withRegisteredPool(poolToken) returns (bool) {
        _approve(poolToken, sender, spender, amount);
        return true;
    }

    function transferFrom(
        address poolToken,
        address spender,
        address from,
        address to,
        uint256 amount
    ) public withRegisteredPool(poolToken) returns (bool) {
        _spendAllowance(poolToken, from, spender, amount);
        _transfer(poolToken, from, to, amount);
        return true;
    }

    function _mint(address poolToken, address to, uint256 amount) internal {
        require(to != address(0), "ERC20: mint to the zero address");

        _totalSupply[poolToken] += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _accountBPTBalances[poolToken][to] += amount;
        }

        BalancerPoolToken(poolToken).emitTransfer(address(0), to, amount);
    }

    function _burn(address poolToken, address from, uint256 amount) internal {
        require(from != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _accountBPTBalances[poolToken][from];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");

        unchecked {
            _accountBPTBalances[poolToken][from] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply[poolToken] -= amount;
        }

        BalancerPoolToken(poolToken).emitTransfer(from, address(0), amount);
    }

    function _transfer(address poolToken, address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 fromBalance = _accountBPTBalances[poolToken][from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _accountBPTBalances[poolToken][from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _accountBPTBalances[poolToken][to] += amount;
        }

        BalancerPoolToken(poolToken).emitTransfer(from, to, amount);
    }

    function _approve(address poolToken, address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[poolToken][owner][spender] = amount;
        BalancerPoolToken(poolToken).emitApprove(owner, spender, amount);
    }

    function _spendAllowance(address poolToken, address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(poolToken, owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(poolToken, owner, spender, currentAllowance - amount);
            }
        }
    }
}
