// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";
import { BaseExtremeAmountsTest } from "./utils/BaseExtremeAmountsTest.sol";

contract LinearPoolExtremeAmountsTest is BaseExtremeAmountsTest {
    using CastingHelpers for *;

    function setUp() public virtual override {
        BaseExtremeAmountsTest.setUp();
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool - DAI/USDC";
        string memory symbol = "ERC20_POOL_DAI_USDC";

        newPool = address(new PoolMock(IVault(address(vault)), name, symbol));
        vm.label(newPool, label);

        PoolFactoryMock(poolFactory).registerTestPool(
            newPool,
            vault.buildTokenConfig(tokens.asIERC20()),
            address(0),
            lp
        );

        poolArgs = abi.encode(vault, name, symbol);
    }

    function _boundBalances(uint256[2] memory balancesRaw) internal pure override returns (uint256[] memory balances) {
        balances = new uint256[](2);
        balances[0] = bound(balancesRaw[0], MIN_BALANCE, MAX_BALANCE);
        balances[1] = balances[0];
    }
}
