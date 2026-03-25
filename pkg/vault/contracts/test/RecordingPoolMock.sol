// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolMock } from "./PoolMock.sol";

contract RecordingPoolMock is PoolMock {
    uint256[] private _lastBalancesScaled18;
    SwapKind public lastKind;
    uint256 public lastAmountGivenScaled18;
    uint256 public lastIndexIn;
    uint256 public lastIndexOut;

    constructor(IVault vault, string memory name, string memory symbol) PoolMock(vault, name, symbol) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getLastBalancesScaled18() external view returns (uint256[] memory) {
        return _lastBalancesScaled18;
    }

    function onSwap(PoolSwapParams calldata params) external virtual override returns (uint256 amountCalculated) {
        delete _lastBalancesScaled18;
        for (uint256 i = 0; i < params.balancesScaled18.length; ++i) {
            _lastBalancesScaled18.push(params.balancesScaled18[i]);
        }
        lastKind = params.kind;
        lastAmountGivenScaled18 = params.amountGivenScaled18;
        lastIndexIn = params.indexIn;
        lastIndexOut = params.indexOut;

        // Return 0 so this test doesn't depend on Vault reserves for tokenOut transfers.
        return 0;
    }
}
