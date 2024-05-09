// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { ERC4626BufferPoolFactory } from "vault/contracts/factories/ERC4626BufferPoolFactory.sol";
import { ERC4626BufferPool } from "vault/contracts/ERC4626BufferPool.sol";

import { BaseVaultTest } from "vault/test/foundry/utils/BaseVaultTest.sol";

// IMPORTANT: this is a fork test. Make sure the env variable MAINNET_RPC_URL is set!
contract ERC4626WrapperValidation is BaseVaultTest {
    ERC4626BufferPoolFactory factory;

    IERC4626 waDAI = IERC4626(0x098256c06ab24F5655C5506A6488781BD711c14b);
    IERC4626 waUSDC = IERC4626(0x57d20c946A7A3812a7225B881CdcD8431D23431C);

    address constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Using older block number because convertToAssets function is bricked in the new version of the aToken wrapper
    uint256 constant BLOCK_NUMBER = 17965150;

    function setUp() public virtual override {
        vm.createSelectFork({ blockNumber: BLOCK_NUMBER, urlOrAlias: "mainnet" });

        BaseVaultTest.setUp();

        factory = new ERC4626BufferPoolFactory(IVault(address(vault)), 365 days);
    }

    // Test must have "Fork" in the name to be matched
    function testFactoryWithInvalidWrapper__Fork() public {
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626BufferPoolFactory.IncompatibleWrappedToken.selector, DAI_ADDRESS)
        );

        // Try to create with regular DAI
        factory.ensureValidWrappedToken(IERC4626(DAI_ADDRESS));
    }

    // Test must have "Fork" in the name to be matched
    function testFactoryWithValidWrappers__Fork() public view {
        // These real ones should not revert
        factory.ensureValidWrappedToken(waDAI);
        factory.ensureValidWrappedToken(waUSDC);
    }
}
