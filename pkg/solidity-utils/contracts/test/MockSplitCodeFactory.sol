// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../helpers/BaseSplitCodeFactory.sol";

contract MockFactoryCreatedContract {
    bytes32 private _id;

    constructor(bytes32 id) {
        require(id != 0, "NON_ZERO_ID");
        _id = id;
    }

    function getId() external view returns (bytes32) {
        return _id;
    }
}

contract MockSplitCodeFactory is BaseSplitCodeFactory {
    event ContractCreated(address destination);

    constructor() BaseSplitCodeFactory(type(MockFactoryCreatedContract).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function create(bytes32 id, bytes32 salt) external returns (address) {
        address destination = _create2(abi.encode(id), salt);
        emit ContractCreated(destination);

        return destination;
    }
}
