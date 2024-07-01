// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ERC20MultiToken } from "../token/ERC20MultiToken.sol";

contract ERC20MultiTokenMock is ERC20MultiToken {
    // #region View functions
    function totalSupply(address pool) public view returns (uint256) {
        return _totalSupply(pool);
    }

    function balanceOf(address pool, address account) public view returns (uint256) {
        return _balanceOf(pool, account);
    }

    function allowance(address pool, address owner, address spender) public view returns (uint256) {
        return _allowance(pool, owner, spender);
    }

    function getMinimumTotalSupply() public pure returns (uint256) {
        return _MINIMUM_TOTAL_SUPPLY;
    }

    // #endregion

    // #region Mutable functions
    function manualQueryModeBalanceIncrease(address pool, address to, uint256 amount) public {
        _queryModeBalanceIncrease(pool, to, amount);
    }

    function manualMint(address pool, address to, uint256 amount) public {
        _mint(pool, to, amount);
    }

    function manualEnsureMinimumTotalSupply(uint256 newTotalSupply) public pure {
        _ensureMinimumTotalSupply(newTotalSupply);
    }

    function manualMintMinimumSupplyReserve(address pool) public {
        _mintMinimumSupplyReserve(pool);
    }

    function manualBurn(address pool, address from, uint256 amount) public {
        _burn(pool, from, amount);
    }

    function manualTransfer(address pool, address from, address to, uint256 amount) public {
        _transfer(pool, from, to, amount);
    }

    function manualApprove(address pool, address owner, address spender, uint256 amount) public {
        _approve(pool, owner, spender, amount);
    }

    function manualSpendAllowance(address pool, address owner, address spender, uint256 amount) public {
        _spendAllowance(pool, owner, spender, amount);
    }
    // #endregion
}
