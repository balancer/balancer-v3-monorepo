// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IStdMedusaCheats {
    // Set block.timestamp
    function warp(uint256) external;

    // Set block.number
    function roll(uint256) external;

    // Set block.basefee
    function fee(uint256) external;

    // Set block.difficulty and block.prevrandao
    function difficulty(uint256) external;

    // Set block.chainid
    function chainId(uint256) external;

    // Sets the block.coinbase
    function coinbase(address) external;

    // Loads a storage slot from an address
    function load(address account, bytes32 slot) external returns (bytes32);

    // Stores a value to an address' storage slot
    function store(address account, bytes32 slot, bytes32 value) external;

    // Sets the *next* call's msg.sender to be the input address
    function prank(address) external;

    // Set msg.sender to the input address until the current call exits
    function prankHere(address) external;

    // Sets an address' balance
    function deal(address who, uint256 newBalance) external;

    // Sets an address' code
    function etch(address who, bytes calldata code) external;

    // Signs data
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);

    // Computes address for a given private key
    function addr(uint256 privateKey) external returns (address);

    // Gets the nonce of an account
    function getNonce(address account) external returns (uint64);

    // Sets the nonce of an account
    // The new nonce must be higher than the current nonce of the account
    function setNonce(address account, uint64 nonce) external;

    // Performs a foreign function call via terminal
    function ffi(string[] calldata) external returns (bytes memory);

    // Take a snapshot of the current state of the EVM
    function snapshot() external returns (uint256);

    // Revert state back to a snapshot
    function revertTo(uint256) external returns (bool);

    // Convert Solidity types to strings
    function toString(address) external returns (string memory);

    function toString(bytes calldata) external returns (string memory);

    function toString(bytes32) external returns (string memory);

    function toString(bool) external returns (string memory);

    function toString(uint256) external returns (string memory);

    function toString(int256) external returns (string memory);

    // Convert strings into Solidity types
    function parseBytes(string memory) external returns (bytes memory);

    function parseBytes32(string memory) external returns (bytes32);

    function parseAddress(string memory) external returns (address);

    function parseUint(string memory) external returns (uint256);

    function parseInt(string memory) external returns (int256);

    function parseBool(string memory) external returns (bool);
}
