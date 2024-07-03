// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiToken.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { AggRouter } from "../../contracts/AggRouter.sol";
import { RouterCommon } from "../../contracts/RouterCommon.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract AggRouterTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal usdcAmountIn = 1e3 * 1e6;
    uint256 internal daiAmountIn = 1e3 * 1e18;
    uint256 internal daiAmountOut = 1e2 * 1e18;
    uint256 internal ethAmountIn = 1e3 ether;
    uint256 internal initBpt = 10e18;
    uint256 internal bptAmountOut = 1e18;

    PoolMock internal wethPool;
    PoolMock internal wethPoolNoInit;

    // Track the indices for the local dai/weth pool.
    uint256 internal daiIdxWethPool;
    uint256 internal wethIdx;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    uint256[] internal wethDaiAmountsIn;
    IERC20[] internal wethDaiTokens;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");
        vm.label(address(newPool), "pool");

        factoryMock.registerTestPool(
            address(newPool),
            vault.buildTokenConfig([address(dai), address(usdc)].toMemoryArray().asIERC20()),
            poolHooksContract,
            lp
        );
        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        wethPool = new PoolMock(IVault(address(vault)), "ERC20 weth Pool", "ERC20POOL");
        vm.label(address(wethPool), "wethPool");

        factoryMock.registerTestPool(
            address(wethPool),
            vault.buildTokenConfig([address(dai), address(weth)].toMemoryArray().asIERC20()),
            poolHooksContract,
            lp
        );

        (daiIdxWethPool, wethIdx) = getSortedIndexes(address(dai), address(weth));

        wethDaiTokens = InputHelpers.sortTokens([address(weth), address(dai)].toMemoryArray().asIERC20());

        wethDaiAmountsIn = new uint256[](2);
        wethDaiAmountsIn[wethIdx] = ethAmountIn;
        wethDaiAmountsIn[daiIdxWethPool] = daiAmountIn;

        wethPoolNoInit = new PoolMock(IVault(address(vault)), "ERC20 weth Pool", "ERC20POOL");
        vm.label(address(wethPoolNoInit), "wethPoolNoInit");

        factoryMock.registerTestPool(
            address(wethPoolNoInit),
            vault.buildTokenConfig([address(weth), address(dai)].toMemoryArray().asIERC20()),
            poolHooksContract,
            lp
        );

        return address(newPool);
    }

    function initPool() internal override {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);

        vm.prank(lp);
        router.initialize(address(pool), tokens, [poolInitAmount, poolInitAmount].toMemoryArray(), 0, false, "");

        vm.prank(lp);
        bool wethIsEth = true;
        router.initialize{ value: ethAmountIn }(
            address(wethPool),
            wethDaiTokens,
            wethDaiAmountsIn,
            initBpt,
            wethIsEth,
            bytes("")
        );
    }

    function testSwapDonated() public {
        require(weth.balanceOf(alice) == defaultBalance, "Precondition: wrong WETH balance");

        bool wethIsEth = false;

        vm.prank(alice);
        weth.transfer(address(vault), ethAmountIn);

        vm.prank(alice);
        uint256 outputTokenAmount = aggRouter.swapSingleTokenDonated(
            address(wethPool),
            weth,
            dai,
            ethAmountIn,
            0,
            MAX_UINT256,
            wethIsEth,
            ""
        );

        assertEq(weth.balanceOf(alice), defaultBalance - ethAmountIn, "Wrong WETH balance");
        assertEq(dai.balanceOf(alice), defaultBalance + outputTokenAmount, "Wrong DAI balance");
    }
}
