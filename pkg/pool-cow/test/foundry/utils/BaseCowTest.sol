// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ICowRouter } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowRouter.sol";
import { PoolRoleAccounts, LiquidityManagement } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { CowRouter } from "../../../contracts/CowRouter.sol";

contract BaseCowTest is BaseVaultTest {
    using CastingHelpers for address[];

    uint256 internal constant _INITIAL_PROTOCOL_FEE_PERCENTAGE = 1e16;

    ICowRouter internal cowRouter;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        super.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        cowRouter = new CowRouter(vault, _INITIAL_PROTOCOL_FEE_PERCENTAGE);

        authorizer.grantRole(
            CowRouter(address(cowRouter)).getActionId(ICowRouter.setProtocolFeePercentage.selector),
            admin
        );

        _approveCowRouterForAllUsers();

        if (pool != address(0)) {
            approveCowRouterForPool(IERC20(pool));
        }
    }

    // Creates a linear pool as a Cow Pool.
    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "Cow AMM Pool";
        string memory symbol = "COWPOOL";

        newPool = PoolFactoryMock(poolFactory).createPool(name, symbol);
        vm.label(newPool, label);

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.enableDonation = true;

        PoolFactoryMock(poolFactory).registerPool(
            newPool,
            vault.buildTokenConfig(tokens.asIERC20()),
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );

        poolArgs = abi.encode(vault, name, symbol);
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
            tokens[i].approve(address(cowRouter), type(uint160).max);
        }

        for (uint256 i = 0; i < erc4626Tokens.length; ++i) {
            erc4626Tokens[i].approve(address(cowRouter), type(uint160).max);
        }
    }

    function approveCowRouterForPool(IERC20 bpt) internal {
        for (uint256 i = 0; i < users.length; ++i) {
            vm.startPrank(users[i]);
            bpt.approve(address(cowRouter), type(uint256).max);
            vm.stopPrank();
        }
    }
}
