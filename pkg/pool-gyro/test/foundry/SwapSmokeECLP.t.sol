// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { GyroEclpPoolDeployer } from "./utils/GyroEclpPoolDeployer.sol";

contract SwapSmokeECLPTest is BaseVaultTest, GyroEclpPoolDeployer {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address, bytes memory) {
        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);
        return createGyroEclpPool(tokens, rateProviders, label, vault, lp);
    }

    function testSwapExactInAndExactOut_smoke() public {
        IERC20[] memory ts = IPoolInfo(pool).getTokens();
        IERC20 token0 = ts[0];
        IERC20 token1 = ts[1];

        vm.startPrank(lp);
        uint256 outAmt = router.swapSingleTokenExactIn(
            pool,
            token0,
            token1,
            1e18,
            0,
            type(uint256).max,
            false,
            bytes("")
        );
        assertGt(outAmt, 0);

        uint256 inAmt = router.swapSingleTokenExactOut(
            pool,
            token1,
            token0,
            1e15,
            type(uint256).max,
            type(uint256).max,
            false,
            bytes("")
        );
        assertGt(inAmt, 0);
        vm.stopPrank();
    }
}
