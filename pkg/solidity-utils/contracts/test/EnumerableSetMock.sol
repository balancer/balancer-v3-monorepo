// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "../openzeppelin/EnumerableSet.sol";

// solhint-disable func-name-mixedcase

contract EnumerableAddressSetMock {
    using EnumerableSet for EnumerableSet.AddressSet;

    event OperationResult(bool result);

    EnumerableSet.AddressSet private _set;

    function contains(address key) public view returns (bool) {
        return _set.contains(key);
    }

    function add(address member) public {
        bool result = _set.add(member);
        emit OperationResult(result);
    }

    function indexOf(address member) public view returns (uint256) {
        return _set.indexOf(member);
    }

    function unchecked_indexOf(address member) public view returns (uint256) {
        return _set.unchecked_indexOf(member);
    }

    function remove(address member) public {
        bool result = _set.remove(member);
        emit OperationResult(result);
    }

    function length() public view returns (uint256) {
        return _set.length();
    }

    function at(uint256 index) public view returns (address member) {
        return _set.at(index);
    }
}
