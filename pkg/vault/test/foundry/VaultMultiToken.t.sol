// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IERC20Errors } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/tokens/IERC20Errors.sol";
import { AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { ERC20PoolMock } from "../../contracts/test/ERC20PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

contract VaultMultiTokenTest is Test {
    using AssetHelpers for address;
    using AssetHelpers for address[];
    using AssetHelpers for address[];
    using ArrayHelpers for address[2];
    using ArrayHelpers for uint256[2];

    VaultMock vault;
    Router router;
    ERC20PoolMock pool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant USDC_AMOUNT_IN = 1e3 * 1e6;
    uint256 constant DAI_AMOUNT_IN = 1e3 * 1e18;

    function setUp() public {
        vault = new VaultMock(30 days, 90 days);
        router = new Router(IVault(vault), address(0));
        USDC = new ERC20TestToken("USDC", "USDC", 6);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        pool = new ERC20PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            address(0),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            true
        );

        USDC.mint(bob, USDC_AMOUNT_IN);
        DAI.mint(bob, DAI_AMOUNT_IN);

        USDC.mint(alice, USDC_AMOUNT_IN);
        DAI.mint(alice, DAI_AMOUNT_IN);

        vm.startPrank(bob);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.startPrank(alice);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(address(USDC), "USDC");
        vm.label(address(DAI), "DAI");
    }

    function testMint() public {
        vm.prank(alice);
        router.mint(USDC, USDC_AMOUNT_IN);

        assertEq(USDC.balanceOf(alice), 0);
        assertEq(USDC.balanceOf(address(vault)), USDC_AMOUNT_IN);

        assertEq(vault.balanceOf(address(USDC), alice), USDC_AMOUNT_IN);
    }

    function testBurn() public {
        vm.prank(alice);
        router.mint(USDC, USDC_AMOUNT_IN);

        assertEq(USDC.balanceOf(alice), 0);
        assertEq(USDC.balanceOf(address(vault)), USDC_AMOUNT_IN);

        assertEq(vault.balanceOf(address(USDC), alice), USDC_AMOUNT_IN);

        vm.prank(alice);
        vault.approve(address(USDC), alice, address(vault), type(uint256).max);
        vm.prank(alice);
        router.burn(USDC, USDC_AMOUNT_IN);

        assertEq(USDC.balanceOf(alice), USDC_AMOUNT_IN);
        assertEq(USDC.balanceOf(address(vault)), 0);

        assertEq(vault.balanceOf(address(USDC), alice), 0);
    }

    function testApprove() public {
        vault.mintERC20(address(USDC), address(this), 1337);

        vault.approve(address(USDC), address(this), address(0xBEEF), 1337);

        assertEq(vault.allowance(address(USDC), address(this), address(0xBEEF)), 1337);
    }
}
