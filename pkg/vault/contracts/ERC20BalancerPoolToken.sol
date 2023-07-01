// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract ERC20BalancerPoolToken is IERC20, IERC20Metadata, IVaultErrors {
    IVault private immutable _vault;

    string private _name;
    string private _symbol;

    modifier onlyVault() {
        if (msg.sender != address(_vault)) {
            revert SenderIsNotVault(msg.sender);
        }
        _;
    }

    constructor(IVault vault, string memory name_, string memory symbol_) {
        _vault = vault;
        _name = name_;
        _symbol = symbol_;
    }

    /// @inheritdoc IERC20Metadata
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @inheritdoc IERC20Metadata
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @inheritdoc IERC20Metadata
    function decimals() public pure override returns (uint8) {
        // Always 18 decimals for BPT.
        return 18;
    }

    function totalSupply() public view override returns (uint256) {
        return _vault.totalSupply(address(this));
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _vault.balanceOf(address(this), account);
    }

    //TODO This is a placeholder until we have pools (at least MockPools). A real pool would register itself
    // in its constructor, and we wouldn't need this. (The factory would just be msg.sender.)
    // Remove when we have pools.
    function initialize(address factory, IERC20[] memory tokens) external {
        _vault.registerPool(factory, tokens);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        // Vault will perform the transfer and call emitTransfer to emit the event from this contract.
        _vault.transfer(address(this), msg.sender, to, amount);
        return true;
    }

    function emitTransfer(address from, address to, uint256 amount) external onlyVault {
        emit Transfer(from, to, amount);
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _vault.allowance(address(this), owner, spender);
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        // Vault will perform the approval and call emitApprove to emit the event from this contract.
        _vault.approve(address(this), msg.sender, spender, amount);
        return true;
    }

    function emitApprove(address owner, address spender, uint256 amount) external onlyVault {
        emit Approval(owner, spender, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // Vault will perform the transfer and call emitTransfer to emit the event from this contract.
        _vault.transferFrom(address(this), msg.sender, from, to, amount);
        return true;
    }
}
