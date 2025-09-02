// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

contract HypercorePrecompileMock {
    bytes internal _data;
    bool internal _shouldRevert = false;

    function setShouldRevert(bool shouldRevert) external {
        _shouldRevert = shouldRevert;
    }

    function setData(bytes memory data) external {
        _data = data;
    }

    fallback(bytes calldata) external returns (bytes memory) {
        if (_shouldRevert) {
            revert();
        }
        return _data;
    }
}
