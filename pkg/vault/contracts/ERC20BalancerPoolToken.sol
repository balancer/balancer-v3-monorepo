// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @notice Base contract for all ERC20 Balancer pools. Often abbreviated as "BPT" = Balancer Pool Token.
 * @dev These are the base of all ERC20 pools; there is a corresponding contract for ERC721 Pools.
 */
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

    /// @inheritdoc IERC20
    function totalSupply() public view override returns (uint256) {
        return _vault.totalSupply(address(this));
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view override returns (uint256) {
        return _vault.balanceOf(address(this), account);
    }

    /// @inheritdoc IERC20
    function transfer(address to, uint256 amount) public override returns (bool) {
        // Vault will perform the transfer and call emitTransfer to emit the event from this contract.
        _vault.transfer(msg.sender, to, amount);
        return true;
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _vault.allowance(address(this), owner, spender);
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 amount) public override returns (bool) {
        // Vault will perform the approval and call emitApprove to emit the event from this contract.
        _vault.approve(msg.sender, spender, amount);
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // Vault will perform the transfer and call emitTransfer to emit the event from this contract.
        _vault.transferFrom(msg.sender, from, to, amount);
        return true;
    }

    // Accounting is centralized in the Vault MultiToken contract, and the actual transfers and approvals
    // are done there. Operations can be initiated from either the token contract or the Vault.
    // To maintain compliance with the ERC-20 standard, and conform to the expections of off-chain processes,
    // all events are emitted from the token contract.

    function emitTransfer(address from, address to, uint256 amount) external onlyVault {
        emit Transfer(from, to, amount);
    }

    function emitApprove(address owner, address spender, uint256 amount) external onlyVault {
        emit Approval(owner, spender, amount);
    }
}
