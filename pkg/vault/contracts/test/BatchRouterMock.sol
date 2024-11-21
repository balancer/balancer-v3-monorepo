// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import {
    AddressToUintMappingSlot
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";
import {
    TransientEnumerableSet
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/TransientEnumerableSet.sol";

import { BatchRouter } from "../BatchRouter.sol";

string constant MOCK_BATCH_ROUTER_VERSION = "Mock BatchRouter v1";

contract BatchRouterMock is BatchRouter {
    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2
    ) BatchRouter(vault, weth, permit2, MOCK_BATCH_ROUTER_VERSION) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function manualGetCurrentSwapTokensInSlot() external view returns (bytes32) {
        TransientEnumerableSet.AddressSet storage enumerableSet = _currentSwapTokensIn();

        bytes32 slot;
        assembly {
            slot := enumerableSet.slot
        }

        return slot;
    }

    function manualGetCurrentSwapTokensOutSlot() external view returns (bytes32) {
        TransientEnumerableSet.AddressSet storage enumerableSet = _currentSwapTokensOut();

        bytes32 slot;
        assembly {
            slot := enumerableSet.slot
        }

        return slot;
    }

    function manualGetCurrentSwapTokenInAmounts() external view returns (AddressToUintMappingSlot) {
        return _currentSwapTokenInAmounts();
    }

    function manualGetCurrentSwapTokenOutAmounts() external view returns (AddressToUintMappingSlot) {
        return _currentSwapTokenOutAmounts();
    }

    function manualGetSettledTokenAmounts() external view returns (AddressToUintMappingSlot) {
        return _settledTokenAmounts();
    }
}
