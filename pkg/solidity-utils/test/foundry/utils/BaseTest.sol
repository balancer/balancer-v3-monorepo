// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ERC20TestToken } from "../../../contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "../../../contracts/test/WETHTestToken.sol";

abstract contract BaseTest is Test, GasSnapshot {
    // Reasonable block.timestamp `MAY_1_2023`
    uint32 internal constant START_TIMESTAMP = 1_682_899_200;

    uint256 internal constant MAX_UINT256 = type(uint256).max;
    // Raw token balances are stored in half a slot, so the max is uint128.
    uint256 internal constant MAX_UINT128 = type(uint128).max;

    // Default admin.
    address payable internal admin;
    uint256 internal adminKey;
    // Default liquidity provider.
    address payable internal lp;
    uint256 internal lpKey;
    // Default user.
    address payable internal alice;
    uint256 internal aliceKey;
    // Default counterparty.
    address payable internal bob;
    uint256 internal bobKey;
    // Malicious user.
    address payable internal hacker;
    uint256 internal hackerKey;
    // Broke user.
    address payable internal broke;
    uint256 internal brokeUserKey;

    // List of all users
    address payable[] internal users;
    uint256[] internal userKeys;

    // ERC20 tokens used for tests.
    ERC20TestToken internal dai;
    ERC20TestToken internal usdc;
    WETHTestToken internal weth;
    ERC20TestToken internal wsteth;
    ERC20TestToken internal veBAL;

    // List of all ERC20 tokens
    IERC20[] internal tokens;

    // Default balance for accounts
    uint256 internal defaultBalance = 1e9 * 1e18;

    function setUp() public virtual {
        // Set timestamp only if testing locally
        if (block.chainid == 31337) {
            // Set block.timestamp to something better than 0
            vm.warp(START_TIMESTAMP);
        }

        // Deploy the base test contracts.
        dai = createERC20("DAI", 18);
        usdc = createERC20("USDC", 18);
        wsteth = createERC20("WSTETH", 18);
        weth = new WETHTestToken();
        vm.label(address(weth), "WETH");
        veBAL = createERC20("veBAL", 18);

        // Fill the token list.
        tokens.push(dai);
        tokens.push(usdc);
        tokens.push(weth);
        tokens.push(wsteth);

        // Create users for testing.
        (admin, adminKey) = createUser("admin");
        (lp, lpKey) = createUser("lp");
        (alice, aliceKey) = createUser("alice");
        (bob, bobKey) = createUser("bob");
        (hacker, hackerKey) = createUser("hacker");
        address brokeNonPay;
        (brokeNonPay, brokeUserKey) = makeAddrAndKey("broke");
        broke = payable(brokeNonPay);
        vm.label(broke, "broke");

        // Fill the users list
        users.push(admin);
        userKeys.push(adminKey);
        users.push(lp);
        userKeys.push(lpKey);
        users.push(alice);
        userKeys.push(aliceKey);
        users.push(bob);
        userKeys.push(bobKey);
        users.push(broke);
        userKeys.push(brokeUserKey);
    }

    function getSortedIndexes(
        address tokenA,
        address tokenB
    ) internal pure returns (uint256 idxTokenA, uint256 idxTokenB) {
        idxTokenA = tokenA > tokenB ? 1 : 0;
        idxTokenB = idxTokenA == 0 ? 1 : 0;
    }

    /// @dev Creates an ERC20 test token, labels its address.
    function createERC20(string memory name, uint8 decimals) internal returns (ERC20TestToken token) {
        token = new ERC20TestToken(name, name, decimals);
        vm.label(address(token), name);
    }

    /// @dev Generates a user, labels its address, and funds it with test assets.
    function createUser(string memory name) internal returns (address payable, uint256) {
        (address user, uint256 key) = makeAddrAndKey(name);
        vm.label(user, name);
        vm.deal(payable(user), defaultBalance);

        for (uint256 i = 0; i < tokens.length; ++i) {
            deal(address(tokens[i]), user, defaultBalance);
        }

        return (payable(user), key);
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

    /// @dev Returns `amount - amount/base`; e.g., if base = 100, decrease `amount` by 1%; if 1000, 0.1%, etc.
    function less(uint256 amount, uint256 base) internal pure returns (uint256) {
        return (amount * (base - 1)) / base;
    }
}
