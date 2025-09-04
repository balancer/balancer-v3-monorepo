// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../SingletonAuthentication.sol";

/**
 * @author Balancer Labs
 * @title AuthenticatedContractMock
 * @notice Generic authenticated contract
 * @dev A general purpose contract that can be used for testing permissioned functions in a more abstract way,
 * to test Authorizer functionality independent of specific Vault functions.
 */
contract AuthenticatedContractMock is SingletonAuthentication {
    event ProtectedFunctionCalled(bytes data);
    event SecondProtectedFunctionCalled(bytes data);

    constructor(IVault vault) SingletonAuthentication(vault) {}

    function protectedFunction(bytes calldata data) external authenticate returns (bytes memory) {
        emit ProtectedFunctionCalled(data);
        return data;
    }

    function secondProtectedFunction(bytes calldata data) external authenticate returns (bytes memory) {
        emit SecondProtectedFunctionCalled(data);
        return data;
    }
}
