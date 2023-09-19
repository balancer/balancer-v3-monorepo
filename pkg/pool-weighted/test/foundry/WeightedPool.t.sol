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

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";

contract WeightedPoolTest is Test {
    using AssetHelpers for address[];
    using AssetHelpers for address[];
    using ArrayHelpers for address[2];
    using ArrayHelpers for uint256[2];

    VaultMock vault;
    Router router;
    WeightedPool pool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    address alice = vm.addr(1);

    uint256 constant USDC_AMOUNT_IN = 1e3 * 1e6;
    uint256 constant DAI_AMOUNT_IN = 1e3 * 1e18;

    function setUp() public {
        vault = new VaultMock(30 days, 90 days);
        router = new Router(IVault(vault), address(0));
        USDC = new ERC20TestToken("USDC", "USDC", 6);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        pool = new WeightedPool(
            WeightedPool.NewPoolParams({
                name: "ERC20 Pool",
                symbol: "ERC20POOL",
                tokens: [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
                normalizedWeights: [uint256(0.50e18), uint256(0.50e18)].toMemoryArray()
            }),
            vault,
            30 days,
            90 days
        );

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

    function testAddLiquidity() public {
        vm.startPrank(alice);
        (uint256[] memory amountsIn, uint256 bptAmountOut) = router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            IBasePool.AddLiquidityKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
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
            IBasePool.AddLiquidityKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            bytes("")
        );

        pool.approve(address(vault), type(uint256).max);

        (uint256[] memory amountsOut, ) = router.removeLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [uint256(DAI_AMOUNT_IN), uint256(USDC_AMOUNT_IN)].toMemoryArray(),
            DAI_AMOUNT_IN,
            IBasePool.RemoveLiquidityKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
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
