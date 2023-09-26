// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IERC20Errors } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/tokens/IERC20Errors.sol";
import { AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { ERC20PoolMock } from "../../contracts/test/ERC20PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { PoolConfigLib } from "../../contracts/lib/PoolConfigLib.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

contract VaultSwapTest is Test {
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

        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.shouldCallAfterSwap = true;
        vault.setConfig(address(pool), config);

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

    function testOnAfterSwapHook() public {
        vm.prank(alice);
        router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            bytes("")
        );

        pool.setMultiplier(1e30);

        vm.prank(bob);
        // should not fail
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            USDC_AMOUNT_IN,
            DAI_AMOUNT_IN,
            type(uint256).max,
            bytes("")
        );
    }

    function testOnAfterSwapHookRevert() public {
        vm.prank(alice);
        router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            bytes("")
        );

        pool.setMultiplier(1e30);

        pool.setFailOnAfterSwap(true);
        vm.prank(bob);
        // should not fail
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.HookCallFailed.selector));
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            USDC_AMOUNT_IN,
            DAI_AMOUNT_IN,
            type(uint256).max,
            bytes("")
        );
    }
}
