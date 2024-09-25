// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

abstract contract BaseContractsDeployer is Test {
    bool reusingArtifacts;

    constructor() {
        reusingArtifacts = vm.envOr("REUSING_HARDHAT_ARTIFACTS", false);
    }

    function _create3(bytes memory constructorArgs, bytes memory bytecode, bytes32 salt) internal returns (address) {
        return CREATE3.deploy(salt, abi.encodePacked(bytecode, constructorArgs), 0);
    }
}
