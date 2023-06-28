// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import "@balancer-labs/v3-solidity-utils/contracts/helpers/TemporarilyPausable.sol";

import "./PoolTokens.sol";
import "./ERC721MultiToken.sol";
import "./PoolRegistry.sol";

contract Vault is IVault, PoolTokens, ERC721MultiToken, PoolRegistry, ReentrancyGuard, TemporarilyPausable {
    // solhint-disable-next-line var-name-mixedcase
    IWETH private immutable _weth;

    constructor(
        IWETH weth,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration) {
        _weth = weth;
    }

    /*******************/
    /*  ERC20 tokens  */
    /*******************/

    /// @inheritdoc IVault
    function totalSupply(address poolToken) external view override returns (uint256) {
        return _getTotalSupply(poolToken);
    }

    /// @inheritdoc IVault
    function balanceOf(address poolToken, address account) external view override returns (uint256) {
        return _getBalanceOf(poolToken, account);
    }

    /// @inheritdoc IVault
    function allowance(address poolToken, address owner, address spender) external view override returns (uint256) {
        return _getAllowance(poolToken, owner, spender);
    }

    /// @inheritdoc IVault
    function transfer(
        address poolToken,
        address owner,
        address to,
        uint256 amount
    ) external withRegisteredPool(poolToken) returns (bool) {
        _transfer(poolToken, owner, to, amount);
        return true;
    }

    /// @inheritdoc IVault
    function approve(
        address poolToken,
        address sender,
        address spender,
        uint256 amount
    ) external withRegisteredPool(poolToken) returns (bool) {
        _approve(poolToken, sender, spender, amount);
        return true;
    }

    /// @inheritdoc IVault
    function transferFrom(
        address poolToken,
        address spender,
        address from,
        address to,
        uint256 amount
    ) external withRegisteredPool(poolToken) returns (bool) {
        _spendAllowance(poolToken, from, spender, amount);
        _transfer(poolToken, from, to, amount);
        return true;
    }

    /*******************/
    /*  ERC721 tokens  */
    /*******************/

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

    /***********************/
    /*  Pool Registration  */
    /***********************/

    /// @inheritdoc IVault
    function registerPool(address factory, IERC20[] memory tokens) external override nonReentrant whenNotPaused {
        _registerPool(factory, tokens);
    }

    /// @inheritdoc IVault
    function isRegisteredPool(address pool) external view returns (bool) {
        return _isRegisteredPool(pool);
    }

    /// @inheritdoc IVault
    function getPoolTokens(
        address pool
    ) external view override withRegisteredPool(pool) returns (IERC20[] memory tokens, uint256[] memory balances) {
        return _getPoolTokens(pool);
    }

    /// @inheritdoc IVault
    function WETH() public view override returns (IWETH) {
        // solhint-disable-previous-line func-name-mixedcase
        return _weth;
    }
}
