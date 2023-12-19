// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";
import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";

contract BalancerPoolTokenTest is Test {
    using ArrayHelpers for *;

    VaultMock vault;
    BasicAuthorizerMock authorizer;
    PoolMock token;
    ERC20TestToken USDC;
    ERC20TestToken DAI;

    uint256 constant AMOUNT = 1e18;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        USDC = new ERC20TestToken("USDC", "USDC", 6);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        IRateProvider[] memory rateProviders = new IRateProvider[](2);

        token = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(USDC), address(DAI)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );
    }

    function testMetadata() public {
        assertEq(token.name(), "ERC20 Pool");
        assertEq(token.symbol(), "ERC20POOL");
        assertEq(token.decimals(), 18);
    }

    function testMint() public {
        vault.mintERC20(address(token), address(0xBEEF), AMOUNT);

        assertEq(token.balanceOf(address(0xBEEF)), AMOUNT);
    }

    function testMintMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(IVault.TotalSupplyTooLow.selector, 1));
        vault.mintERC20(address(token), address(0xBEEF), 1);
    }

    function testBurn() public {
        vault.mintERC20(address(token), address(0xBEEF), AMOUNT);
        vault.burnERC20(address(token), address(0xBEEF), AMOUNT - 1e6);

        assertEq(token.balanceOf(address(0xBEEF)), 1e6);
    }

    function testBurnMinimum() public {
        vault.mintERC20(address(token), address(0xBEEF), AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IVault.TotalSupplyTooLow.selector, 0));
        vault.burnERC20(address(token), address(0xBEEF), AMOUNT);
    }

    function testApprove() public {
        vault.mintERC20(address(token), address(this), AMOUNT);

        token.approve(address(0xBEEF), AMOUNT);

        assertEq(token.allowance(address(this), address(0xBEEF)), AMOUNT);
    }

    function testTransfer() public {
        vault.mintERC20(address(token), address(this), 1e18);

        assertTrue(token.transfer(address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        vault.mintERC20(address(token), address(from), AMOUNT);

        vm.prank(from);
        token.approve(address(this), AMOUNT);

        token.transferFrom(from, address(0xBEEF), AMOUNT);

        assertEq(token.allowance(from, address(0xBEEF)), 0);
        assertEq(token.balanceOf(address(0xBEEF)), AMOUNT);
        assertEq(token.balanceOf(from), 0);
    }

    function testMintToZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, 0));
        vault.mintERC20(address(token), address(0), AMOUNT);
    }

    function testTransferFromToZero() public {
        vault.mintERC20(address(token), address(this), AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, AMOUNT)
        );
        token.transferFrom(address(this), address(0), AMOUNT);
    }
}
