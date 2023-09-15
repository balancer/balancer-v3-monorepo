// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/token/IERC20MultiToken.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @notice A full ERC20 compatible token with all the data and implementation delegated to the ERC20Multitoken contract
 */
contract ERC20FacadeToken is IERC20, IERC20Metadata {
    /**
     * @dev Error indicating that the sender is not a MultiToken.
     */
    error SenderIsNotMultiToken(address sender);

    IERC20MultiToken private immutable _multiToken;

    string private _name;
    string private _symbol;

    modifier onlyMultiToken() {
        if (msg.sender != address(_multiToken)) {
            revert SenderIsNotMultiToken(msg.sender);
        }
        _;
    }

    constructor(IERC20MultiToken multiToken_, string memory name_, string memory symbol_) {
        _multiToken = multiToken_;
        _name = name_;
        _symbol = symbol_;
    }

    /// @inheritdoc IERC20Metadata
    function name() public view returns (string memory) {
        return _name;
    }

    /// @inheritdoc IERC20Metadata
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /// @inheritdoc IERC20Metadata
    function decimals() public pure returns (uint8) {
        // Always 18 decimals for BPT.
        return 18;
    }

    /// @inheritdoc IERC20
    function totalSupply() public view returns (uint256) {
        return _multiToken.totalSupply(address(this));
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view returns (uint256) {
        return _multiToken.balanceOf(address(this), account);
    }

    /// @inheritdoc IERC20
    function transfer(address to, uint256 amount) public returns (bool) {
        // MultiToken will perform the transfer and call emitTransfer to emit the event from this contract.
        _multiToken.transferWith(msg.sender, to, amount);
        return true;
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) public view returns (uint256) {
        return _multiToken.allowance(address(this), owner, spender);
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 amount) public returns (bool) {
        // MultiToken will perform the approval and call emitApprove to emit the event from this contract.
        _multiToken.approveWith(msg.sender, spender, amount);
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        // MultiToken will perform the transfer and call emitTransfer to emit the event from this contract.
        _multiToken.transferFromWith(msg.sender, from, to, amount);
        return true;
    }

    /// Accounting is centralized in the MultiToken contract, and the actual transfers and approvals
    /// are done there. Operations can be initiated from either the token contract or the MultiToken.
    ///
    /// To maintain compliance with the ERC-20 standard, and conform to the expections of off-chain processes,
    /// the MultiToken calls `emitTransfer` and `emitApprove` during those operations, so that the event is emitted
    /// only from the token contract. These events are NOT defined in the MultiToken contract.

    /// @dev Emit the Transfer event. This function can only be called by the MultiToken.
    function emitTransfer(address from, address to, uint256 amount) external onlyMultiToken {
        emit Transfer(from, to, amount);
    }

    /// @dev Emit the Approval event. This function can only be called by the MultiToken.
    function emitApprove(address owner, address spender, uint256 amount) external onlyMultiToken {
        emit Approval(owner, spender, amount);
    }
}
