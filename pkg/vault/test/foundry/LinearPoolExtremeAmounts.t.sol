// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { BaseExtremeAmountsTest } from "./utils/BaseExtremeAmountsTest.sol";

contract LinearPoolExtremeAmountsTest is BaseExtremeAmountsTest {
    using ArrayHelpers for *;
    using CastingHelpers for *;

    function setUp() public virtual override {
        BaseExtremeAmountsTest.setUp();
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        address newPool = address(new PoolMock(IVault(address(vault)), "ERC20 Pool - DAI/USDC", "ERC20_POOL_DAI_USDC"));
        vm.label(newPool, label);

        factoryMock.registerTestPool(newPool, vault.buildTokenConfig(tokens.asIERC20()), address(0), lp);

        return address(newPool);
    }
}
