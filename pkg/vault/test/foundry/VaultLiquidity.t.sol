// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

contract VaultLiquidityTest is Test {
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

    uint256 constant USDC_AMOUNT_IN = 1e3 * 1e6;
    uint256 constant DAI_AMOUNT_IN = 1e3 * 1e18;
    uint256 private constant MINIMUM_BPT = 1e6;

    function setUp() public {
        vault = new VaultMock(30 days, 90 days);
        router = new Router(IVault(vault), address(0));
        USDC = new ERC20TestToken("USDC", "USDC", 6);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        pool = new ERC20PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(USDC)].toMemoryArray().asIERC20()
        );
        pool.register(address(0));

        USDC.mint(alice, USDC_AMOUNT_IN);
        DAI.mint(alice, DAI_AMOUNT_IN);

        vm.startPrank(alice);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.label(alice, "alice");
        vm.label(address(USDC), "USDC");
        vm.label(address(DAI), "DAI");
    }

    function testMinimalSupply() public {
        assertEq(pool.totalSupply(), MINIMUM_BPT);
    }

    function testAddLiquidity() public {
        vm.startPrank(alice);
        (uint256[] memory amountsIn, uint256 bptAmountOut) = router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            bytes("")
        );
        vm.stopPrank();

        // asssets are transferred from Alice
        assertEq(USDC.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(alice), 0);

        // assets are stored in the Vault
        assertEq(USDC.balanceOf(address(vault)), USDC_AMOUNT_IN);
        assertEq(DAI.balanceOf(address(vault)), DAI_AMOUNT_IN);

        // assets are deposited to the pool
        (, uint256[] memory balances) = vault.getPoolTokens(address(pool));
        assertEq(balances[0], DAI_AMOUNT_IN);
        assertEq(balances[1], USDC_AMOUNT_IN);

        // amountsIn should be correct
        assertEq(amountsIn[0], DAI_AMOUNT_IN);
        assertEq(amountsIn[1], USDC_AMOUNT_IN);

        // should mint correct amount of BPT tokens
        assertEq(pool.balanceOf(alice), bptAmountOut);
        assertEq(bptAmountOut, DAI_AMOUNT_IN);
    }

    function testRemoveLiquidity() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            bytes("")
        );

        pool.approve(address(vault), type(uint256).max);

        uint256[] memory amountsOut = router.removeLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            bytes("")
        );

        vm.stopPrank();

        // asssets are transferred from Alice
        assertEq(USDC.balanceOf(alice), USDC_AMOUNT_IN);
        assertEq(DAI.balanceOf(alice), DAI_AMOUNT_IN);

        // assets are stored in the Vault
        assertEq(USDC.balanceOf(address(vault)), 0);
        assertEq(DAI.balanceOf(address(vault)), 0);

        // assets are deposited to the pool
        (, uint256[] memory balances) = vault.getPoolTokens(address(pool));
        assertEq(balances[0], 0);
        assertEq(balances[1], 0);

        // amountsOut are correct
        assertEq(amountsOut[0], DAI_AMOUNT_IN);
        assertEq(amountsOut[1], USDC_AMOUNT_IN);
    }
}
