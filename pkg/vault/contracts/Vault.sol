// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import { ReentrancyGuard } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import { TemporarilyPausable } from "@balancer-labs/v3-solidity-utils/contracts/helpers/TemporarilyPausable.sol";

import { ERC20MultiToken } from "./ERC20MultiToken.sol";
import { ERC721MultiToken } from "./ERC721MultiToken.sol";
import { PoolRegistry } from "./PoolRegistry.sol";

contract Vault is IVault, ERC20MultiToken, ERC721MultiToken, PoolRegistry, ReentrancyGuard, TemporarilyPausable {
    // solhint-disable-next-line var-name-mixedcase
    IWETH private immutable _weth;

    constructor(
        IWETH weth,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration) {
        _weth = weth;
    }

    /*******************************************************************************
                              ERC20 Balancer Pool Tokens
    *******************************************************************************/

    /// @inheritdoc IVault
    function totalSupplyOfERC20(address poolToken) external view returns (uint256) {
        return _totalSupplyOfERC20(poolToken);
    }

    /// @inheritdoc IVault
    function balanceOfERC20(address poolToken, address account) external view returns (uint256) {
        return _balanceOfERC20(poolToken, account);
    }

    /// @inheritdoc IVault
    function allowanceOfERC20(address poolToken, address owner, address spender) external view returns (uint256) {
        return _allowanceOfERC20(poolToken, owner, spender);
    }

    /// @inheritdoc IVault
    function transferERC20(
        address owner,
        address to,
        uint256 amount
    ) external withRegisteredPool(msg.sender) returns (bool) {
        _transferERC20(msg.sender, owner, to, amount);
        return true;
    }

    /// @inheritdoc IVault
    function approveERC20(
        address sender,
        address spender,
        uint256 amount
    ) external withRegisteredPool(msg.sender) returns (bool) {
        _approveERC20(msg.sender, sender, spender, amount);
        return true;
    }

    /// @inheritdoc IVault
    function transferFromERC20(
        address spender,
        address from,
        address to,
        uint256 amount
    ) external withRegisteredPool(msg.sender) returns (bool) {
        _spendAllowance(msg.sender, from, spender, amount);
        _transferERC20(msg.sender, from, to, amount);
        return true;
    }

    /*******************************************************************************
                            ERC721 Balancer Pool Tokens
    *******************************************************************************/

    /// @inheritdoc IVault
    function balanceOfERC721(address token, address owner) external view returns (uint256) {
        return _balanceOfERC721(token, owner);
    }

    /// @inheritdoc IVault
    function ownerOfERC721(address token, uint256 tokenId) external view returns (address) {
        return _safeOwnerOfERC721(token, tokenId);
    }

    /// @inheritdoc IVault
    function getApprovedERC721(address token, uint256 tokenId) external view returns (address) {
        return _getApprovedERC721(token, tokenId);
    }

    /// @inheritdoc IVault
    function isApprovedForAllERC721(address token, address owner, address operator) external view returns (bool) {
        return _isApprovedForAllERC721(token, owner, operator);
    }

    /// @inheritdoc IVault
    function approveERC721(address sender, address to, uint256 tokenId) external withRegisteredPool(msg.sender) {
        _approveERC721(msg.sender, sender, to, tokenId);
    }

    /// @inheritdoc IVault
    function setApprovalForAllERC721(
        address sender,
        address operator,
        bool approved
    ) external withRegisteredPool(msg.sender) {
        _setApprovalForAllERC721(msg.sender, sender, operator, approved);
    }

    /// @inheritdoc IVault
    function transferFromERC721(
        address sender,
        address from,
        address to,
        uint256 tokenId
    ) public withRegisteredPool(msg.sender) {
        _transferFromERC721(msg.sender, sender, from, to, tokenId);
    }

    /// @inheritdoc IVault
    function safeTransferFromERC721(
        address sender,
        address from,
        address to,
        uint256 tokenId
    ) external withRegisteredPool(msg.sender) {
        _safeTransferFromERC721(msg.sender, sender, from, to, tokenId);
    }

    /// @inheritdoc IVault
    function safeTransferFromERC721(
        address sender,
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) external withRegisteredPool(msg.sender) {
        _safeTransferFromERC721(msg.sender, sender, from, to, tokenId, data);
    }

    /*******************************************************************************
                                    Pool Registration
    *******************************************************************************/

    /// @inheritdoc IVault
    function registerPool(address factory, IERC20[] memory tokens) external nonReentrant whenNotPaused {
        _registerPool(factory, tokens);
    }

    /// @inheritdoc IVault
    function isRegisteredPool(address pool) external view returns (bool) {
        return _isRegisteredPool(pool);
    }

    /// @inheritdoc IVault
    function getPoolTokens(
        address pool
    ) external view withRegisteredPool(pool) returns (IERC20[] memory tokens, uint256[] memory balances) {
        return _getPoolTokens(pool);
    }

    /// @inheritdoc IVault
    function WETH() public view returns (IWETH) {
        // solhint-disable-previous-line func-name-mixedcase
        return _weth;
    }
}
