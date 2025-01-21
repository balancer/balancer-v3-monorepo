// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ICowRouter } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowRouter.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { CowRouter } from "../../../contracts/CowRouter.sol";

contract BaseCowTest is BaseVaultTest {
    ICowRouter internal cowRouter;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public override {
        super.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        cowRouter = new CowRouter(vault, permit2);

        authorizer.grantRole(
            CowRouter(address(cowRouter)).getActionId(ICowRouter.setProtocolFeePercentage.selector),
            admin
        );

        _approveCowRouterForAllUsers();

        if (pool != address(0)) {
            approveCowRouterForPool(IERC20(pool));
        }
    }

    function _approveCowRouterForAllUsers() private {
        for (uint256 i = 0; i < users.length; ++i) {
            address user = users[i];
            vm.startPrank(user);
            approveCowRouterForSender();
            vm.stopPrank();
        }
    }

    function approveCowRouterForSender() internal {
        for (uint256 i = 0; i < tokens.length; ++i) {
            permit2.approve(address(tokens[i]), address(cowRouter), type(uint160).max, type(uint48).max);
        }

        for (uint256 i = 0; i < erc4626Tokens.length; ++i) {
            permit2.approve(address(erc4626Tokens[i]), address(cowRouter), type(uint160).max, type(uint48).max);
        }
    }

    function approveCowRouterForPool(IERC20 bpt) internal {
        for (uint256 i = 0; i < users.length; ++i) {
            vm.startPrank(users[i]);
            bpt.approve(address(cowRouter), type(uint256).max);
            permit2.approve(address(bpt), address(cowRouter), type(uint160).max, type(uint48).max);
            vm.stopPrank();
        }
    }
}
