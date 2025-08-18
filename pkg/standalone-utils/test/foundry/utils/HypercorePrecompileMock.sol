// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

contract HypercorePrecompileMock {
    bytes internal data;

    function setData(bytes memory _data) external {
        data = _data;
    }

    fallback(bytes calldata) external returns (bytes memory) {
        return data;
    }
}
