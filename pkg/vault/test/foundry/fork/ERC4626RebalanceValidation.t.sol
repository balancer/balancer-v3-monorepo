// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, PoolConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";

import { ERC4626BufferPoolFactoryMock } from "../utils/ERC4626BufferPoolFactoryMock.sol";
import { ERC4626BufferPoolMock } from "../utils/ERC4626BufferPoolMock.sol";
import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
import { PoolConfigBits, PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";

import { BaseVaultTest } from "vault/test/foundry/utils/BaseVaultTest.sol";

contract ERC4626RebalanceValidation is BaseVaultTest {
    using ArrayHelpers for *;

    ERC4626BufferPoolFactoryMock factory;
    ERC4626BufferPoolMock internal bufferPool;

    IERC20 daiMainnet;
    IERC20 aDaiMainnet;
    IERC4626 waDAI;

    // uint256 constant BLOCK_NUMBER = 18985254;
    // Using older block number because convertToAssets function is bricked in the new version of the aToken wrapper
    uint256 constant BLOCK_NUMBER = 17965150;
    uint256 POOL_AMPLIFICATION = 1e18;

    address constant aDAI_ADDRESS = 0x098256c06ab24F5655C5506A6488781BD711c14b;
    address constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Owner of DAI and USDC in Mainnet
    address constant DONOR_WALLET_ADDRESS = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

    address payable donor;

    uint256 constant INIT_DAI_AMOUNT = 1e4 * 1e18;
    uint256 constant INIT_A_DAI_AMOUNT = INIT_DAI_AMOUNT / 10;
    uint256 initADaiAmount;

    uint256 constant DELTA = 1e12;

    uint256 internal bptAmountOut;

    function setUp() public virtual override {
        vm.createSelectFork({ blockNumber: BLOCK_NUMBER, urlOrAlias: "mainnet" });

        donor = payable(DONOR_WALLET_ADDRESS);
        vm.label(donor, "TokenDonor");

        daiMainnet = IERC20(DAI_ADDRESS);
        aDaiMainnet = IERC20(aDAI_ADDRESS);
        waDAI = IERC4626(aDAI_ADDRESS);

        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        factory = new ERC4626BufferPoolFactoryMock(IVault(address(vault)), 365 days);
        bufferPool = ERC4626BufferPoolMock(_createBuffer(waDAI));
        return address(bufferPool);
    }

    function initPool() internal override {
        transferTokensFromDonorToUsers();

        vm.startPrank(lp);
        initADaiAmount = waDAI.convertToShares(INIT_A_DAI_AMOUNT);
        waDAI.deposit(INIT_A_DAI_AMOUNT, address(lp));
        uint256[] memory amountsIn = [uint256(initADaiAmount), uint256(INIT_DAI_AMOUNT)].toMemoryArray();
        bptAmountOut = router.initialize(
            address(bufferPool),
            [aDAI_ADDRESS, DAI_ADDRESS].toMemoryArray().asIERC20(),
            amountsIn,
            // Account for the precision loss
            INIT_DAI_AMOUNT - DELTA - 1e6,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function transferTokensFromDonorToUsers() internal {
        address[] memory usersToTransfer = [address(bob), address(lp)].toMemoryArray();

        for (uint256 index = 0; index < usersToTransfer.length; index++) {
            address userAddress = usersToTransfer[index];

            vm.startPrank(donor);
            daiMainnet.transfer(userAddress, 50 * INIT_DAI_AMOUNT);
            vm.stopPrank();

            vm.startPrank(userAddress);
            daiMainnet.approve(address(vault), type(uint256).max);
            aDaiMainnet.approve(address(vault), type(uint256).max);
            daiMainnet.approve(address(waDAI), type(uint256).max);
            vm.stopPrank();
        }
    }

    function testInitialize() public {
        // Tokens are stored in the Vault
        assertEq(aDaiMainnet.balanceOf(address(vault)), initADaiAmount);
        assertEq(daiMainnet.balanceOf(address(vault)), INIT_DAI_AMOUNT);

        // Tokens are deposited to the pool
        (, , uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(bufferPool));
        assertEq(balances[0], initADaiAmount);
        assertEq(balances[1], INIT_DAI_AMOUNT);

        // should mint correct amount of BPT tokens
        // Account for the precision loss
        assertApproxEqAbs(bufferPool.balanceOf(lp), bptAmountOut, DELTA);
        assertApproxEqAbs(bptAmountOut, INIT_DAI_AMOUNT + INIT_A_DAI_AMOUNT, DELTA);
    }

    function testRebalance() public {
        bufferPool.rebalance();
    }

    //    function testSwapDaiToUsdcGivenIn() public {
    //        uint256 DAI_AMOUNT_IN = 100 * 1e18;
    //        uint256 USDC_AMOUNT_OUT = 100 * 1e6;
    //
    //        uint256 bobInitialUsdcBalance = usdcMainnet.balanceOf(bob);
    //        uint256 bobInitialDaiBalance = daiMainnet.balanceOf(bob);
    //
    //        uint256 vaultInitialWrappedUsdcBalance = aUsdcMainnet.balanceOf(address(vault));
    //        uint256 vaultInitialWrappedDaiBalance = aDaiMainnet.balanceOf(address(vault));
    //
    //        vm.prank(bob);
    //        uint256 amountCalculated = router.swapExactIn(
    //            address(stablePool),
    //            daiMainnet,
    //            usdcMainnet,
    //            DAI_AMOUNT_IN,
    //            less(USDC_AMOUNT_OUT, 1e3),
    //            type(uint256).max,
    //            false,
    //            bytes("")
    //        );
    //
    //        uint256 wrappedDaiIn = waDAI.convertToShares(DAI_AMOUNT_IN);
    //        uint256 wrappedUsdcOut = waUSDC.convertToShares(amountCalculated);
    //
    //        // Tokens are transferred from Bob
    //        assertEq(usdcMainnet.balanceOf(bob), bobInitialUsdcBalance + amountCalculated);
    //        assertEq(daiMainnet.balanceOf(bob), bobInitialDaiBalance - DAI_AMOUNT_IN);
    //
    //        // Assert that the amount received is close from expected
    //        assertApproxEqAbs(amountCalculated, USDC_AMOUNT_OUT, 1e3);
    //
    //        // Underlying tokens were wrapped and are not in the vault
    //        assertApproxEqAbs(usdcMainnet.balanceOf(address(vault)), 0, 1);
    //        assertApproxEqAbs(daiMainnet.balanceOf(address(vault)), 0, 1);
    //
    //        // Wrapped tokens are stored in the vault
    //        assertApproxEqAbs(aUsdcMainnet.balanceOf(address(vault)), vaultInitialWrappedUsdcBalance - wrappedUsdcOut, 1);
    //        assertApproxEqAbs(aDaiMainnet.balanceOf(address(vault)), vaultInitialWrappedDaiBalance + wrappedDaiIn, 1);
    //
    //        // Tokens are deposited to the pool
    //        (, , , uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(stablePool));
    //        assertEq(balances[0], vaultInitialWrappedDaiBalance + wrappedDaiIn);
    //        assertEq(balances[1], vaultInitialWrappedUsdcBalance - wrappedUsdcOut);
    //    }
    //
    //    function testSwapUsdcToDaiGivenIn() public {
    //        uint256 USDC_AMOUNT_IN = 300 * 1e6;
    //        uint256 DAI_AMOUNT_OUT = 300 * 1e18;
    //
    //        uint256 bobInitialUsdcBalance = usdcMainnet.balanceOf(bob);
    //        uint256 bobInitialDaiBalance = daiMainnet.balanceOf(bob);
    //
    //        uint256 vaultInitialWrappedUsdcBalance = aUsdcMainnet.balanceOf(address(vault));
    //        uint256 vaultInitialWrappedDaiBalance = aDaiMainnet.balanceOf(address(vault));
    //
    //        vm.prank(bob);
    //        uint256 amountCalculated = router.swapExactIn(
    //            address(stablePool),
    //            usdcMainnet,
    //            daiMainnet,
    //            USDC_AMOUNT_IN,
    //            less(DAI_AMOUNT_OUT, 1e3),
    //            type(uint256).max,
    //            false,
    //            bytes("")
    //        );
    //
    //        uint256 wrappedUsdcIn = waUSDC.convertToShares(USDC_AMOUNT_IN);
    //        uint256 wrappedDaiOut = waDAI.convertToShares(amountCalculated);
    //
    //        // Tokens are transferred from Bob
    //        assertEq(usdcMainnet.balanceOf(bob), bobInitialUsdcBalance - USDC_AMOUNT_IN);
    //        assertEq(daiMainnet.balanceOf(bob), bobInitialDaiBalance + amountCalculated);
    //
    //        // Assert that the amount received is close from expected
    //        assertApproxEqAbs(amountCalculated, DAI_AMOUNT_OUT, 1e9);
    //
    //        // Underlying tokens were wrapped and are not in the vault
    //        assertApproxEqAbs(usdcMainnet.balanceOf(address(vault)), 0, 1);
    //        assertApproxEqAbs(daiMainnet.balanceOf(address(vault)), 0, 1);
    //
    //        // Wrapped tokens are stored in the vault
    //        assertApproxEqAbs(aUsdcMainnet.balanceOf(address(vault)), vaultInitialWrappedUsdcBalance + wrappedUsdcIn, 1);
    //        assertApproxEqAbs(aDaiMainnet.balanceOf(address(vault)), vaultInitialWrappedDaiBalance - wrappedDaiOut, 1);
    //
    //        // Tokens are deposited to the pool
    //        (, , , uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(stablePool));
    //        assertEq(balances[0], vaultInitialWrappedDaiBalance - wrappedDaiOut);
    //        assertEq(balances[1], vaultInitialWrappedUsdcBalance + wrappedUsdcIn);
    //    }
    //
    //    function testSwapDaiToUsdcGivenOut() public {
    //        uint256 DAI_AMOUNT_IN = 100 * 1e18;
    //        uint256 USDC_AMOUNT_OUT = 100 * 1e6;
    //
    //        uint256 bobInitialUsdcBalance = usdcMainnet.balanceOf(bob);
    //        uint256 bobInitialDaiBalance = daiMainnet.balanceOf(bob);
    //
    //        uint256 vaultInitialWrappedUsdcBalance = aUsdcMainnet.balanceOf(address(vault));
    //        uint256 vaultInitialWrappedDaiBalance = aDaiMainnet.balanceOf(address(vault));
    //
    //        vm.prank(bob);
    //        uint256 amountCalculated = router.swapExactOut(
    //            address(stablePool),
    //            daiMainnet,
    //            usdcMainnet,
    //            USDC_AMOUNT_OUT,
    //            more(DAI_AMOUNT_IN, 1e3),
    //            type(uint256).max,
    //            false,
    //            bytes("")
    //        );
    //
    //        uint256 wrappedDaiIn = waDAI.convertToShares(amountCalculated);
    //        uint256 wrappedUsdcOut = waUSDC.convertToShares(USDC_AMOUNT_OUT);
    //
    //        // Tokens are transferred from Bob
    //        assertEq(usdcMainnet.balanceOf(bob), bobInitialUsdcBalance + USDC_AMOUNT_OUT);
    //        assertEq(daiMainnet.balanceOf(bob), bobInitialDaiBalance - amountCalculated);
    //
    //        // Assert that the amount deposited is close from expected
    //        assertApproxEqAbs(amountCalculated, DAI_AMOUNT_IN, 1e9);
    //
    //        // Underlying tokens were wrapped and are not in the vault
    //        assertApproxEqAbs(usdcMainnet.balanceOf(address(vault)), 0, 1);
    //        assertApproxEqAbs(daiMainnet.balanceOf(address(vault)), 0, 1);
    //
    //        // Wrapped tokens are stored in the vault
    //        assertApproxEqAbs(aUsdcMainnet.balanceOf(address(vault)), vaultInitialWrappedUsdcBalance - wrappedUsdcOut, 1);
    //        assertApproxEqAbs(aDaiMainnet.balanceOf(address(vault)), vaultInitialWrappedDaiBalance + wrappedDaiIn, 1);
    //
    //        // Tokens are deposited to the pool
    //        (, , , uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(stablePool));
    //        assertEq(balances[0], vaultInitialWrappedDaiBalance + wrappedDaiIn);
    //        assertEq(balances[1], vaultInitialWrappedUsdcBalance - wrappedUsdcOut);
    //    }

    function less(uint256 amount, uint256 base) internal pure returns (uint256) {
        return (amount * (base - 1)) / base;
    }

    function more(uint256 amount, uint256 base) internal pure returns (uint256) {
        return (amount * (base + 1)) / base;
    }

    function _createBuffer(IERC4626 wrappedToken) private returns (address) {
        return factory.create(wrappedToken, address(0), _generateSalt(address(wrappedToken)));
    }

    // Need a unique salt for deployments to work; just use the token address
    function _generateSalt(address token) private pure returns (bytes32) {
        return bytes32(uint256(uint160(token)));
    }
}
