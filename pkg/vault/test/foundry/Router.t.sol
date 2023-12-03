// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { ERC20PoolMock } from "../../contracts/test/ERC20PoolMock.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

contract RouterTest is Test {
    using AssetHelpers for address;
    using AssetHelpers for address[];
    using AssetHelpers for address[];
    using ArrayHelpers for address[2];
    using ArrayHelpers for uint256[2];

    VaultMock vault;
    Router router;
    BasicAuthorizerMock authorizer;
    ERC20PoolMock pool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant USDC_AMOUNT_IN = 1e3 * 1e6;
    uint256 constant DAI_AMOUNT_IN = 1e3 * 1e18;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), address(0));
        USDC = new ERC20TestToken("USDC", "USDC", 6);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        IRateProvider[] memory rateProviders = new IRateProvider[](2);

        pool = new ERC20PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
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

    function testQuerySwap() public {
        vm.prank(alice);
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            0,
            bytes("")
        );

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(EVMCallModeHelpers.NotStaticCall.selector));
        router.querySwap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            USDC_AMOUNT_IN,
            bytes("")
        );
    }

    function testDisableQueries() public {
        vm.prank(alice);
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            0,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));

        vault.disableQuery();

        // Authorize alice
        bytes32 disableQueryRole = vault.getActionId(IVault.disableQuery.selector);

        authorizer.grantRole(disableQueryRole, alice);

        vm.prank(alice);
        vault.disableQuery();

        vm.expectRevert(abi.encodeWithSelector(IVault.QueriesDisabled.selector));

        vm.prank(address(0), address(0));
        router.querySwap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            USDC_AMOUNT_IN,
            bytes("")
        );
    }
}
