// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/SafeERC20.sol";
import "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import "@balancer-labs/v3-solidity-utils/contracts/math/Math.sol";

import "../AssetTransfersHandler.sol";

contract MockAssetTransfersHandler is AssetTransfersHandler {
    using Math for uint256;
    using SafeERC20 for IERC20;

    mapping(address => mapping(IERC20 => uint256)) private _internalTokenBalance;

    constructor(IWETH weth) AssetHelpers(weth) {}

    function receiveAsset(
        IAsset asset,
        uint256 amount,
        address sender,
        bool fromInternalBalance
    ) external payable {
        _receiveAsset(asset, amount, sender, fromInternalBalance);
    }

    function sendAsset(
        IAsset asset,
        uint256 amount,
        address payable recipient,
        bool toInternalBalance
    ) external {
        _sendAsset(asset, amount, recipient, toInternalBalance);
    }

    function getInternalBalance(address account, IERC20 token) external view returns (uint256) {
        return _internalTokenBalance[account][token];
    }

    function depositToInternalBalance(
        address account,
        IERC20 token,
        uint256 amount
    ) external {
        token.safeTransferFrom(account, address(this), amount);
        _increaseInternalBalance(account, token, amount);
    }

    function _increaseInternalBalance(
        address account,
        IERC20 token,
        uint256 amount
    ) internal override {
        _internalTokenBalance[account][token] += amount;
    }

    function _decreaseInternalBalance(
        address account,
        IERC20 token,
        uint256 amount,
        bool capped
    ) internal override returns (uint256 deducted) {
        uint256 currentBalance = _internalTokenBalance[account][token];
        deducted = capped ? Math.min(currentBalance, amount) : amount;
        _internalTokenBalance[account][token] = currentBalance.sub(deducted);
    }
}
