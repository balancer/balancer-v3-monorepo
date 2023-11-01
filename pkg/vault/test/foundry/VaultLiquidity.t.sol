// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IERC20Errors } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/token/IERC20Errors.sol";
import { AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";

import { PoolMock } from "@balancer-labs/v3-pool-utils/contracts/test/PoolMock.sol";
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
    BasicAuthorizerMock authorizer;
    PoolMock pool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant USDC_AMOUNT_IN = 1e3 * 1e6;
    uint256 constant DAI_AMOUNT_IN = 1e3 * 1e18;

    // Tolerances: 0.1 cents.
    uint256 constant USDC_TOLERANCE = 1e6 / 1000;
    uint256 constant DAI_TOLERANCE = 1e18 / 1000;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), address(0));
        USDC = new ERC20TestToken("USDC", "USDC", 6);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        pool = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            address(0),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            true
        );

        USDC.mint(alice, USDC_AMOUNT_IN);
        DAI.mint(alice, DAI_AMOUNT_IN);

        vm.startPrank(alice);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(address(USDC), "USDC");
        vm.label(address(DAI), "DAI");
    }

    function testAddLiquidity() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        vm.startPrank(alice);
        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            IVault.AddLiquidityKind.UNBALANCED,
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

    function testAddLiquidityNotInitialized() public {
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(IVault.PoolNotInitialized.selector, address(pool)));
        router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            IVault.AddLiquidityKind.UNBALANCED,
            bytes("")
        );
    }

    function testRemoveLiquidity() public {
        // Use a different account to initialize so that the main LP is clean at the start of the test.
        _mockInitialize(bob);

        vm.startPrank(alice);

        router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            IVault.AddLiquidityKind.UNBALANCED,
            bytes("")
        );

        (, uint256[] memory amountsOut, ) = router.removeLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            DAI_AMOUNT_IN,
            [uint256(DAI_AMOUNT_IN) - 1e18 / 100, uint256(USDC_AMOUNT_IN) - 1e6 / 100].toMemoryArray(),
            IVault.RemoveLiquidityKind.PROPORTIONAL,
            bytes("")
        );

        vm.stopPrank();

        // assets are transferred back to Alice
        assertApproxEqAbs(USDC.balanceOf(alice), USDC_AMOUNT_IN, USDC_TOLERANCE);
        assertApproxEqAbs(DAI.balanceOf(alice), DAI_AMOUNT_IN, DAI_TOLERANCE);

        // assets are no longer in the vault
        assertApproxEqAbs(USDC.balanceOf(address(vault)), 0, USDC_TOLERANCE);
        assertApproxEqAbs(DAI.balanceOf(address(vault)), 0, DAI_TOLERANCE);

        // assets are not in the pool
        (, uint256[] memory balances) = vault.getPoolTokens(address(pool));
        assertApproxEqAbs(balances[0], 0, DAI_TOLERANCE);
        assertApproxEqAbs(balances[1], 0, USDC_TOLERANCE);

        // amountsOut are correct
        assertApproxEqAbs(amountsOut[0], DAI_AMOUNT_IN, DAI_TOLERANCE);
        assertApproxEqAbs(amountsOut[1], USDC_AMOUNT_IN, USDC_TOLERANCE);

        // Alice has burnt the correct amount of BPT
        assertEq(pool.balanceOf(alice), 0);
    }

    function testRemoveLiquidityNotInitialized() public {
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(IVault.PoolNotInitialized.selector, address(pool)));
        router.removeLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            DAI_AMOUNT_IN,
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            IVault.RemoveLiquidityKind.PROPORTIONAL,
            bytes("")
        );
    }

    function _mockInitialize(address initializer) internal {
        vm.startPrank(initializer);

        // The mock pool can be initialized with no liquidity; it mints some BPT to the initializer
        // to comply with the vault's required minimum.
        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(0), uint256(0)].toMemoryArray(),
            0,
            bytes("")
        );
    }
}
