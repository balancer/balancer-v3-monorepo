// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

abstract contract BaseTest is Test, GasSnapshot {
    using ArrayHelpers for *;

    // Reasonable block.timestamp `MAY_1_2023`
    uint40 internal constant START_TIMESTAMP = 1_682_899_200;

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
    // Broke user.
    address payable broke;

    // ERC20 tokens used for tests.
    ERC20TestToken internal dai;
    ERC20TestToken internal usdc;
    WETHTestToken internal weth;
    ERC20TestToken internal wsteth;

    // List of all ERC20 tokens
    IERC20[] internal tokens;

    // Default balance for accounts
    uint256 internal defaultBalance;

    function setUp() public virtual {
        // Set block.timestamp to something better than 0
        vm.warp(START_TIMESTAMP);

        // Set default balance to 1mil
        defaultBalance = 1e6 * 1e18;

        // Deploy the base test contracts.
        dai = createERC20("DAI", 18);
        usdc = createERC20("USDC", 18);
        wsteth = createERC20("WSTETH", 18);
        weth = new WETHTestToken();
        vm.label(address(weth), "WETH");

        // Fill the token list.
        tokens.push(dai);
        tokens.push(usdc);
        tokens.push(weth);
        tokens.push(wsteth);

        // Create users for testing.
        admin = createUser("admin");
        lp = createUser("lp");
        alice = createUser("alice");
        bob = createUser("bob");
        hacker = createUser("hacker");
        broke = payable(makeAddr("broke"));
        vm.label(broke, "broke");
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
        vm.deal(user, defaultBalance);

        for (uint256 index = 0; index < tokens.length; index++) {
            deal(address(tokens[index]), user, defaultBalance);
        }

        return user;
    }

    function getDecimalScalingFactor(uint8 decimals) internal pure returns (uint256 scalingFactor) {
        require(decimals <= 18, "Decimals must be between 0 and 18");
        uint256 decimalDiff = 18 - decimals;
        scalingFactor = 1e18; // FP1

        for (uint256 i = 0; i < decimalDiff; ++i) {
            scalingFactor *= 10;
        }

        return scalingFactor;
    }
}
