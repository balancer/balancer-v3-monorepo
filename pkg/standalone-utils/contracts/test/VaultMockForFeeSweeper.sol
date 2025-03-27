// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";

contract VaultMockForFeeSweeper is IAuthorizer {
    using SafeERC20 for IERC20;

    mapping(address => bool) public owners;

    constructor() {
        owners[msg.sender] = true;
    }

    modifier onlyOwner() {
        require(owners[msg.sender], "VaultMockForFeeSweeper: Not an owner");
        _;
    }

    function getAuthorizer() external view returns (IAuthorizer authorizer) {
        return IAuthorizer(address(this));
    }

    function canPerform(bytes32, address account, address) external view returns (bool) {
        return owners[account];
    }

    function canPerform(bytes32, address account) external view returns (bool) {
        return owners[account];
    }

    function addOwner(address owner_) external onlyOwner {
        owners[owner_] = true;
    }

    function removeOwner(address owner_) external onlyOwner {
        owners[owner_] = false;
    }

    function getProtocolFeeController() external view returns (IProtocolFeeController protocolFeeController) {
        return IProtocolFeeController(address(this));
    }

    function collectAggregateFees(address) external {}

    function withdrawProtocolFeesForToken(address, address recipient, IERC20 token) external onlyOwner {
        token.safeTransfer(recipient, token.balanceOf(address(this)));
    }
}
