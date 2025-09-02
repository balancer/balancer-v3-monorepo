// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

contract HypercorePrecompileMock {
    bytes internal _data;
    bool internal _shouldRevert = false;
    bool internal _shouldReturnZeroBytes = false;

    function setShouldRevert(bool shouldRevert) external {
        _shouldRevert = shouldRevert;
    }
    function setShouldReturnZeroBytes(bool shouldReturnZeroBytes) external {
        _shouldReturnZeroBytes = shouldReturnZeroBytes;
    }

    function setData(bytes memory data) external {
        _data = data;
    }

    fallback(bytes calldata) external returns (bytes memory) {
        if (_shouldRevert) {
            revert();
        }
        if (_shouldReturnZeroBytes) {
            return abi.encode(0);
        }
        return _data;
    }
}
