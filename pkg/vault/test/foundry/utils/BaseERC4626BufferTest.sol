// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { TokenConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { PoolMock } from "../../../contracts/test/PoolMock.sol";
import { BaseVaultTest } from "./BaseVaultTest.sol";

abstract contract BaseERC4626BufferTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 bufferInitialAmount = 1e5 * 1e18;
    uint256 erc4626PoolInitialAmount = 10e6 * 1e18;
    uint256 erc4626PoolInitialBPTAmount = erc4626PoolInitialAmount * 2;

    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;
    uint256 internal waDaiIdx;
    uint256 internal waUsdcIdx;
    address erc4626Pool;

    // Rounding issues are introduced when dealing with tokens with rates different than 1:1. For example, to scale the
    // tokens of an yield-bearing pool, the amount of tokens is multiplied by the rate of the token, which is
    // calculated using `convertToAssets(FixedPoint.ONE)`. It generates an 18 decimals rate, but quantities bigger than
    // 1e18 will have rounding issues. Another example is the different between convert (used to calculate query
    // results of buffer operations) and the actual operation.
    uint256 internal errorTolerance = 1e8;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _setupWrappedTokens();
        _initializeBuffers();
        _initializeERC4626Pool();
    }

    function testERC4626BufferPreconditions() public view {
        // bob should have the full erc4626Pool BPT. Since BPT amount is based on ERC4626 rates (using rate providers
        // to convert wrapped amounts to underlying amounts), some rounding imprecision can occur. The test below
        // allows an error of 0.00000001%.
        assertApproxEqRel(
            IERC20(erc4626Pool).balanceOf(bob),
            erc4626PoolInitialAmount * 2 - MIN_BPT,
            errorTolerance,
            "Wrong yield-bearing pool BPT amount"
        );

        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(erc4626Pool);
        // The yield-bearing pool should have `erc4626PoolInitialAmount` of both tokens.
        assertEq(address(tokens[waDaiIdx]), address(waDAI), "Wrong yield-bearing pool token (waDAI)");
        assertEq(address(tokens[waUsdcIdx]), address(waUSDC), "Wrong yield-bearing pool token (waUSDC)");
        assertEq(
            balancesRaw[waDaiIdx],
            waDAI.convertToShares(erc4626PoolInitialAmount),
            "Wrong yield-bearing pool balance waDAI"
        );
        assertEq(
            balancesRaw[waUsdcIdx],
            waUSDC.convertToShares(erc4626PoolInitialAmount),
            "Wrong yield-bearing pool balance waUSDC"
        );

        // LP should have correct amount of shares from buffer (invested amount in underlying minus burned "BPTs")
        assertApproxEqAbs(
            vault.getBufferOwnerShares(IERC4626(waDAI), lp),
            2 * bufferInitialAmount - MIN_BPT,
            1, // 1 wei error due to rounding issues
            "Wrong share of waDAI buffer belonging to LP"
        );
        assertApproxEqAbs(
            vault.getBufferOwnerShares(IERC4626(waUSDC), lp),
            2 * bufferInitialAmount - MIN_BPT,
            1, // 1 wei error due to rounding issues
            "Wrong share of waUSDC buffer belonging to LP"
        );

        // Buffer should have the correct amount of issued shares.
        assertApproxEqAbs(
            vault.getBufferTotalShares(IERC4626(waDAI)),
            bufferInitialAmount * 2,
            1, // 1 wei error due to rounding issues
            "Wrong issued shares of waDAI buffer"
        );
        assertApproxEqAbs(
            vault.getBufferTotalShares(IERC4626(waUSDC)),
            bufferInitialAmount * 2,
            1, // 1 wei error due to rounding issues
            "Wrong issued shares of waUSDC buffer"
        );

        uint256 baseBalance;
        uint256 wrappedBalance;

        // The vault buffers should each have `bufferInitialAmount` of their respective tokens.
        (baseBalance, wrappedBalance) = vault.getBufferBalance(IERC4626(waDAI));
        assertEq(baseBalance, bufferInitialAmount, "Wrong waDAI buffer balance for base token");
        assertEq(
            wrappedBalance,
            waDAI.convertToShares(bufferInitialAmount),
            "Wrong waDAI buffer balance for wrapped token"
        );

        (baseBalance, wrappedBalance) = vault.getBufferBalance(IERC4626(waUSDC));
        assertEq(baseBalance, bufferInitialAmount, "Wrong waUSDC buffer balance for base token");
        assertEq(
            wrappedBalance,
            waUSDC.convertToShares(bufferInitialAmount),
            "Wrong waUSDC buffer balance for wrapped token"
        );
    }

    function _initializeBuffers() private {
        // Create and fund buffer pools.
        vm.startPrank(lp);
        dai.mint(lp, bufferInitialAmount);
        dai.approve(address(waDAI), bufferInitialAmount);
        uint256 waDAILPShares = waDAI.deposit(bufferInitialAmount, lp);

        usdc.mint(lp, bufferInitialAmount);
        usdc.approve(address(waUSDC), bufferInitialAmount);
        uint256 waUSDCLPShares = waUSDC.deposit(bufferInitialAmount, lp);
        vm.stopPrank();

        vm.startPrank(lp);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);
        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);

        router.addLiquidityToBuffer(waDAI, bufferInitialAmount, waDAILPShares, lp);
        router.addLiquidityToBuffer(waUSDC, bufferInitialAmount, waUSDCLPShares, lp);
        vm.stopPrank();
    }

    function _initializeERC4626Pool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.WITH_RATE;
        tokenConfig[1].tokenType = TokenType.WITH_RATE;
        tokenConfig[waDaiIdx].rateProvider = IRateProvider(address(waDAI));
        tokenConfig[waUsdcIdx].rateProvider = IRateProvider(address(waUSDC));

        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC4626 Pool", "ERC4626P");

        factoryMock.registerTestPool(address(newPool), tokenConfig, poolHooksContract);

        vm.label(address(newPool), "erc4626 pool");
        erc4626Pool = address(newPool);

        vm.startPrank(bob);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);

        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);

        dai.mint(bob, erc4626PoolInitialAmount);
        dai.approve(address(waDAI), erc4626PoolInitialAmount);
        uint256 waDaiBobShares = waDAI.deposit(erc4626PoolInitialAmount, bob);

        usdc.mint(bob, erc4626PoolInitialAmount);
        usdc.approve(address(waUSDC), erc4626PoolInitialAmount);
        uint256 waUsdcBobShares = waUSDC.deposit(erc4626PoolInitialAmount, bob);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[waDaiIdx] = waDaiBobShares;
        amountsIn[waUsdcIdx] = waUsdcBobShares;

        // Since token rates are rounding down, the BPT calculation may be a little less than the predicted amount.
        _initPool(erc4626Pool, amountsIn, erc4626PoolInitialBPTAmount - errorTolerance - MIN_BPT);

        IERC20(address(erc4626Pool)).approve(address(permit2), MAX_UINT256);
        permit2.approve(address(erc4626Pool), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(erc4626Pool), address(batchRouter), type(uint160).max, type(uint48).max);

        IERC20(address(erc4626Pool)).approve(address(router), type(uint256).max);
        IERC20(address(erc4626Pool)).approve(address(batchRouter), type(uint256).max);
        vm.stopPrank();
    }

    function _setupWrappedTokens() private {
        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        vm.label(address(waDAI), "waDAI");

        // "USDC" is deliberately 18 decimals to test one thing at a time.
        waUSDC = new ERC4626TestToken(usdc, "Wrapped aUSDC", "waUSDC", 18);
        vm.label(address(waUSDC), "waUSDC");

        (waDaiIdx, waUsdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));

        // Manipulate rates before creating the ERC4626 pools. It's important to don't have a 1:1 rate when testing
        // ERC4626 tokens, so we can differ what's wrapped and what's underlying amounts.
        dai.mint(lp, 10 * erc4626PoolInitialAmount);
        usdc.mint(lp, 10 * erc4626PoolInitialAmount);
        // Deposit sets the rate to 1.
        vm.startPrank(lp);
        dai.approve(address(waDAI), 10 * erc4626PoolInitialAmount);
        waDAI.deposit(10 * erc4626PoolInitialAmount, lp);
        usdc.approve(address(waUSDC), 10 * erc4626PoolInitialAmount);
        waUSDC.deposit(10 * erc4626PoolInitialAmount, lp);
        vm.stopPrank();
        // Changing asset balances without minting shares makes the balance be different than 1.
        dai.mint(address(waDAI), 2 * erc4626PoolInitialAmount);
        usdc.mint(address(waUSDC), 4 * erc4626PoolInitialAmount);
    }
}
