// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolInitializer } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolInitializer.sol";
import { IPoolCallbacks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolCallbacks.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { PoolConfigLib } from "../../contracts/lib/PoolConfigLib.sol";
import { RouterAdaptor } from "../../contracts/test/RouterAdaptor.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

contract InitializerTest is Test {
    using ArrayHelpers for *;
    using RouterAdaptor for IRouter;

    VaultMock vault;
    IRouter router;
    BasicAuthorizerMock authorizer;
    PoolMock pool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant BPT_AMOUNT = 2e3 * 1e18;
    uint256 constant BPT_AMOUNT_ROUND_DOWN = BPT_AMOUNT - 1;
    uint256 constant DEFAULT_AMOUNT = 1e3 * 1e18;
    uint256 constant DEFAULT_AMOUNT_ROUND_UP = DEFAULT_AMOUNT + 1;
    uint256 constant DEFAULT_AMOUNT_ROUND_DOWN = DEFAULT_AMOUNT - 1;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), new WETHTestToken());
        USDC = new ERC20TestToken("USDC", "USDC", 18);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        IRateProvider[] memory rateProviders = new IRateProvider[](2);

        pool = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );

        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallAfterInitialize = true;
        vault.setConfig(address(pool), config);

        USDC.mint(bob, DEFAULT_AMOUNT);
        DAI.mint(bob, DEFAULT_AMOUNT);

        USDC.mint(alice, 2 * DEFAULT_AMOUNT);
        DAI.mint(alice, 2 * DEFAULT_AMOUNT);

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

    function testOnAfterInitializeCallback() public {
        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolInitializer.onAfterInitialize.selector,
                [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
                2 * DEFAULT_AMOUNT,
                bytes("0xff")
            )
        );
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }

    function testOnAfterInitializeCallbackRevert() public {
        // should fail
        pool.setFailOnAfterInitializeCallback(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVault.CallbackFailed.selector));
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            0,
            false,
            bytes("0xff")
        );
    }
}
