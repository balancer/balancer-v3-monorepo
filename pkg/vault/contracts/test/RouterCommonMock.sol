// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import { StorageSlotExtension } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";

import { RouterCommon } from "../../contracts/RouterCommon.sol";

contract RouterCommonMock is RouterCommon {
    event CurrentSenderMock(address sender);

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2
    ) RouterCommon(vault, weth, permit2, "Mock RouterCommon v1") {}

    function call(address to, bytes calldata data) external saveSender(msg.sender) returns (bytes memory) {
        (bool success, bytes memory result) = to.call(data);
        require(success, "PoolCommonMock: call failed");
        return result;
    }

    function emitSender() external {
        (bool success, bytes memory result) = address(this).call(
            abi.encodeWithSelector(RouterCommon.getSender.selector)
        );
        require(success, "RouterCommonMock: failed getSender call");

        emit CurrentSenderMock(abi.decode(result, (address)));
    }

    function getVault() external view returns (IVault) {
        return _vault;
    }

    function getWeth() external view returns (IWETH) {
        return _weth;
    }

    function getPermit2() external view returns (IPermit2 permit2) {
        return _permit2;
    }

    function manualGetSenderSlot() external view returns (StorageSlotExtension.AddressSlotType) {
        return _getSenderSlot();
    }

    function mockTakeTokenIn(address sender, IERC20 tokenIn, uint256 amountIn, bool wethIsEth) external {
        _takeTokenIn(sender, tokenIn, amountIn, wethIsEth);
    }

    function mockSendTokenOut(address sender, IERC20 tokenOut, uint256 amountOut, bool wethIsEth) external {
        return _sendTokenOut(sender, tokenOut, amountOut, wethIsEth);
    }

    function manualReturnETH() public payable {
        _returnEth(msg.sender);
    }

    function sendExtraEth(address recipient, uint256 amount) public payable {
        payable(recipient).transfer(amount);
    }

    function assertETHBalance() public payable {
        require(address(msg.sender).balance > 0, "Balance must be more then 0");
    }

    function manualMulticallVoid() external {
        this.multicall(new bytes[](0));
    }

    function manualPermitBatchReentrancy(
        PermitApproval[] calldata permitBatch,
        bytes[] calldata permitSignatures,
        IAllowanceTransfer.PermitBatch calldata permit2Batch,
        bytes calldata permit2Signature
    ) public nonReentrant {
        _permitBatch(permitBatch, permitSignatures, permit2Batch, permit2Signature);
    }
}
