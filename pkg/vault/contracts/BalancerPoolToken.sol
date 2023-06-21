// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BalancerPoolToken is ERC20 {
    IVault private immutable _vault;

    modifier onlyVault() {
        require(msg.sender == address(_vault), "Sender is not the Vault");
        _;
    }

    constructor(IVault vault, string memory name, string memory symbol) ERC20(name, symbol) {
        _vault = vault;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function totalSupply() public view override returns (uint256) {
        return _getVault().totalSupply(address(this));
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _getVault().balanceOf(address(this), account);
    }

    function initialize(IERC20[] memory tokens) external {
        _getVault().registerPool(tokens);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        // Vault will perform the transfer and call emitTransfer to emit the event from this contract.
        _getVault().transfer(address(this), msg.sender, to, amount);
        return true;
    }

    function emitTransfer(address from, address to, uint256 amount) external onlyVault {
        emit Transfer(from, to, amount);
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _getVault().allowance(address(this), owner, spender);
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        // Vault will perform the approval and call emitApprove to emit the event from this contract.
        _getVault().approve(address(this), msg.sender, spender, amount);
        return true;
    }

    function emitApprove(address owner, address spender, uint256 amount) external onlyVault {
        emit Approval(owner, spender, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // Vault will perform the transfer and call emitTransfer to emit the event from this contract.
        _getVault().transferFrom(address(this), msg.sender, from, to, amount);
        return true;
    }

    function _getVault() internal view returns (IVault) {
        return _vault;
    }
}
