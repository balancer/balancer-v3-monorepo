// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { ERC721BalancerPoolToken } from "../../contracts/ERC721BalancerPoolToken.sol";

contract ERC721BalancerPoolTokenTest is Test {
    ERC721BalancerPoolToken token;
    function setUp() public {
        token = new ERC721BalancerPoolToken();
    }
}
