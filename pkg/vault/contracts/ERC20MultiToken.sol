// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20Errors } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/tokens/IERC20Errors.sol";

import { ERC20BalancerPoolToken } from "./ERC20BalancerPoolToken.sol";

/**
 * @notice Store Balancer Pool Token (BPT) data and handle accounting for all Pools in the Vault.
 * @dev The Vault manages all BPT (Balancer Pool Tokens), which can be either ERC20 or ERC721, in a manner similar to
 * ERC-1155, but without fully supporting the standard. Parts of it conflict with the Vault's security model and
 * design philosophy; the purpose is to encapsulate all accounting (of both pool constituent tokens and the pool
 * contracts themselves) in the Vault, rather than dividing responsibilities between the Vault and pool contracts.
 */
abstract contract ERC20MultiToken is IERC20Errors {
    // Pool -> (owner -> balance): Users' BPT balances
    mapping(address => mapping(address => uint256)) private _bptBalances;

    // Pool -> (owner -> (spender -> allowance))
    mapping(address => mapping(address => mapping(address => uint256))) private _allowances;

    // Pool -> total supply (BPT)
    mapping(address => uint256) private _totalSupply;

    function _totalSupplyOfERC20(address poolToken) internal view returns (uint256) {
        return _totalSupply[poolToken];
    }

    function _balanceOfERC20(address poolToken, address account) internal view returns (uint256) {
        return _bptBalances[poolToken][account];
    }

    function _allowanceOfERC20(address poolToken, address owner, address spender) internal view returns (uint256) {
        return _allowances[poolToken][owner][spender];
    }

    function _mintERC20(address poolToken, address to, uint256 amount) internal {
        if (to == address(0)) {
            revert ERC20InvalidReceiver(to);
        }

        _totalSupply[poolToken] += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _bptBalances[poolToken][to] += amount;
        }

        ERC20BalancerPoolToken(poolToken).emitTransfer(address(0), to, amount);
    }

    function _burnERC20(address poolToken, address from, uint256 amount) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(from);
        }

        uint256 accountBalance = _bptBalances[poolToken][from];
        if (amount > accountBalance) {
            revert ERC20InsufficientBalance(from, accountBalance, amount);
        }

        unchecked {
            _bptBalances[poolToken][from] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply[poolToken] -= amount;
        }

        ERC20BalancerPoolToken(poolToken).emitTransfer(from, address(0), amount);
    }

    function _transferERC20(address poolToken, address from, address to, uint256 amount) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(from);
        }

        if (to == address(0)) {
            revert ERC20InvalidReceiver(to);
        }

        uint256 fromBalance = _bptBalances[poolToken][from];
        if (amount > fromBalance) {
            revert ERC20InsufficientBalance(from, fromBalance, amount);
        }

        unchecked {
            _bptBalances[poolToken][from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _bptBalances[poolToken][to] += amount;
        }

        ERC20BalancerPoolToken(poolToken).emitTransfer(from, to, amount);
    }

    function _approveERC20(address poolToken, address owner, address spender, uint256 amount) internal {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(owner);
        }

        if (spender == address(0)) {
            revert ERC20InvalidSpender(spender);
        }

        _allowances[poolToken][owner][spender] = amount;
        ERC20BalancerPoolToken(poolToken).emitApprove(owner, spender, amount);
    }

    function _spendAllowance(address poolToken, address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[poolToken][owner][spender];
        if (currentAllowance != type(uint256).max) {
            if (amount > currentAllowance) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, amount);
            }

            unchecked {
                _approveERC20(poolToken, owner, spender, currentAllowance - amount);
            }
        }
    }
}
