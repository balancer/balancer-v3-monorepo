// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

contract HypercorePrecompileMock {
    bytes internal _data;

    function setData(bytes memory data) external {
        _data = data;
    }

    fallback(bytes calldata) external returns (bytes memory) {
        return _data;
    }
}
