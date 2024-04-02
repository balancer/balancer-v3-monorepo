// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { LiquidityManagement, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { DynamicFeePoolMock } from "../../contracts/test/DynamicFeePoolMock.sol";
import { PoolConfigBits, PoolConfigLib } from "../../contracts/lib/PoolConfigLib.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract DynamicFeePoolTest is BaseVaultTest {
    using ArrayHelpers for *;

    address internal swapPool;
    address internal liquidityPool;
    uint256 internal daiIdx;

    function setUp() public virtual override {
        defaultBalance = 1e10 * 1e18;
        BaseVaultTest.setUp();

        (daiIdx, ) = getSortedIndexes(address(dai), address(usdc));

        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");
    }

    function createPool() internal virtual override returns (address) {
        address[] memory tokens = [address(dai), address(usdc)].toMemoryArray();

        liquidityPool = _createPool(tokens, "liquidityPool");
        swapPool = _createPool(tokens, "swapPool");

        // NOTE: stores address in `pool` (unused in this test)
        return address(0xdead);
    }

    function _createPool(address[] memory tokens, string memory label) internal virtual override returns (address) {
        DynamicFeePoolMock newPool = new DynamicFeePoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");
        vm.label(address(newPool), label);

        factoryMock.registerPool(
            address(newPool),
            vault.buildTokenConfig(tokens.asIERC20()),
            address(0),
            PoolConfigBits.wrap(0).toPoolConfig().hooks,
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: true,
                enableRemoveLiquidityCustom: true
            }),
            true // hasDynamicSwapFee
        );

        return address(newPool);
    }

    function initPool() internal override {
        poolInitAmount = 1e9 * 1e18;

        vm.startPrank(lp);
        _initPool(swapPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(liquidityPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    function testPoolRegistrationDynamicFeeNotSupported() public {
        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");

        // NOTE: declaring tokenConfig before vm.expectRevert to view call from interfering with revert expectation
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolMustSupportDynamicFee.selector));
        factoryMock.registerPool(
            address(newPool),
            tokenConfig,
            address(0),
            PoolConfigBits.wrap(0).toPoolConfig().hooks,
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: true,
                enableRemoveLiquidityCustom: true
            }),
            true // hasDynamicSwapFee
        );
    }

    function testScaffolding() public {
        // NOTE: test that the setup is run correctly
    }
}
