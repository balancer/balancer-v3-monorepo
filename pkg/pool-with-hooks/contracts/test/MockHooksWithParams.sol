// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { PoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseHooks } from "../BaseHooks.sol";

contract MockHooksWithParams is BaseHooks {
    event HookCalled(string hookName);

    struct StructParameters {
        bool boolStructParameter;
        uint uintStructParameter;
        address addressStructParameter;
        string stringStructParameter;
    }

    bool public boolParameter;
    uint public uintParameter;
    address public addressParameter;
    string public stringParameter;
    StructParameters public structParameters;

    constructor(
        bool _boolParameter,
        uint _uintParameter,
        address _addressParameter,
        string memory _stringParameter,
        StructParameters memory _structParameters
    ) {
        boolParameter = _boolParameter;
        uintParameter = _uintParameter;
        addressParameter = _addressParameter;
        stringParameter = _stringParameter;
        structParameters = _structParameters;
    }

    function availableHooks() external pure override returns (PoolHooks memory) {
        return
            PoolHooks({
                shouldCallBeforeInitialize: false,
                shouldCallAfterInitialize: false,
                shouldCallBeforeAddLiquidity: false,
                shouldCallAfterAddLiquidity: false,
                shouldCallBeforeRemoveLiquidity: false,
                shouldCallAfterRemoveLiquidity: false,
                shouldCallBeforeSwap: false,
                shouldCallAfterSwap: false
            }); // All hooks disabled
    }

    function supportsDynamicFee() external pure override returns (bool) {
        return false;
    }
}
