// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

/**
 * @dev Partial ERC20-ish token implementation to mock non strictly ERC20 compliant functions.
 * 
 * For example, `approve` will not return a boolean, and will not allow an amount != 0 if there is any allowance
 * already for the spender upon calling it.
 */
contract USDTMock {
    mapping(address => mapping(address => uint256)) private _allowances;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {}

    function approve(address spender, uint256 amount) public {
        require(!((amount != 0) && (_allowances[msg.sender][spender] != 0)));

        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function setAllowance(address owner, address spender, uint256 amount) external {
        _allowances[owner][spender] = amount;
    }
}
