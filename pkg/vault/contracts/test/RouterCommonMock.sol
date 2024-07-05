// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import { StorageSlotExtension } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";

import { RouterCommon } from "../../contracts/RouterCommon.sol";

contract RouterCommonMock is RouterCommon {
    event CurrentSenderMock(address sender);

    constructor(IVault vault, IWETH weth, IPermit2 permit2) RouterCommon(vault, weth, permit2) {}

    function call(address to, bytes calldata data) external saveSender returns (bytes memory) {
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

    function manualGetSenderSlot() external view returns (StorageSlotExtension.AddressSlotType) {
        return _getSenderSlot();
    }
}
