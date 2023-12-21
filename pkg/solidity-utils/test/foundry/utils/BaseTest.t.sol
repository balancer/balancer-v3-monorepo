// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

abstract contract BaseTest is Test {
    using ArrayHelpers for *;

    // Default admin.
    address payable admin;
    // Default liquidity provider.
    address payable lp;
    // Default user.
    address payable alice;
    // Default counterparty.
    address payable bob;
    // Malicious user.
    address payable hacker;

    ERC20TestToken internal dai;
    ERC20TestToken internal usdc;
    WETHTestToken internal weth;

    function setUp() public virtual {
        // Deploy the base test contracts.
        dai = createERC20("DAI", 18);
        usdc = createERC20("USDC", 18);
        weth = new WETHTestToken();
        vm.label(address(weth), 'WETH');

        // Create users for testing.
        admin = createUser("admin");
        lp = createUser("lp");
        alice = createUser("alice");
        bob = createUser("bob");
        hacker = createUser("hacker");
    }

    /// @dev Creates an ERC20 test token, labels its address.
    function createERC20(string memory name, uint8 decimals) internal returns (ERC20TestToken token) {
        token = new ERC20TestToken(name, name, decimals);
        vm.label(address(token), name);
    }

    /// @dev Generates a user, labels its address, and funds it with test assets.
    function createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.label(user, name);
        vm.deal(user, 100 ether);
        deal(address(dai), user, 1_000_000e18);
        deal(address(usdc), user, 1_000_000e18);
        deal(address(weth), user, 1_000_000e18);
        return user;
    }
}
