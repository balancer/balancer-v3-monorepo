// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "../../../contracts/test/PoolMock.sol";
import { BaseVaultTest } from "./BaseVaultTest.sol";

abstract contract BaseERC4626BufferTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal bufferInitialAmount = 1e5 * 1e18;
    uint256 internal erc4626PoolInitialAmount = 10e6 * 1e18;
    uint256 internal erc4626PoolInitialBPTAmount = erc4626PoolInitialAmount * 2;

    uint256 internal waDaiIdx;
    uint256 internal waWethIdx;

    // Rounding issues are introduced when dealing with tokens with rates different than 1:1. For example, to scale the
    // tokens of an yield-bearing pool, the amount of tokens is multiplied by the rate of the token, which is
    // calculated using `previewRedeem(FixedPoint.ONE)`. It generates an 18 decimal rate, but quantities bigger than
    // 1e18 will have rounding issues. Another example is the different between convert (used to calculate query
    // results of buffer operations) and the actual operation.
    uint256 internal errorTolerance = 1e8;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _initializeBuffers();
    }

    function createPool() internal virtual override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC4626 Pool";
        string memory symbol = "ERC4626P";

        TokenConfig[] memory tokenConfig = getTokenConfig();

        newPool = address(new PoolMock(IVault(address(vault)), name, symbol));
        vm.label(newPool, name);

        factoryMock.registerTestPool(newPool, tokenConfig, poolHooksContract, lp);

        poolArgs = abi.encode(vault, name, symbol);
    }

    function initPool() internal virtual override {
        uint256 waDaiBobShares = _vaultPreviewDeposit(waDAI, erc4626PoolInitialAmount);
        uint256 waWethBobShares = _vaultPreviewDeposit(waWETH, erc4626PoolInitialAmount);

        vm.startPrank(bob);
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[waDaiIdx] = waDaiBobShares;
        amountsIn[waWethIdx] = waWethBobShares;

        // Since token rates are rounding down, the BPT calculation may be a little less than the predicted amount.
        _initPool(pool, amountsIn, erc4626PoolInitialBPTAmount - errorTolerance - BUFFER_MINIMUM_TOTAL_SUPPLY);

        vm.stopPrank();
    }

    function getTokenConfig() internal virtual returns (TokenConfig[] memory) {
        (waDaiIdx, waWethIdx) = getSortedIndexes(address(waDAI), address(waWETH));

        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waWethIdx].token = IERC20(waWETH);
        tokenConfig[0].tokenType = TokenType.WITH_RATE;
        tokenConfig[1].tokenType = TokenType.WITH_RATE;
        tokenConfig[waDaiIdx].rateProvider = IRateProvider(address(waDAI));
        tokenConfig[waWethIdx].rateProvider = IRateProvider(address(waWETH));
        return tokenConfig;
    }

    function testERC4626BufferPreconditions() public {
        // Bob should own all pool BPTs. Since BPT amount is based on ERC4626 rates (using rate providers
        // to convert wrapped amounts to underlying amounts), some rounding imprecision can occur.
        assertApproxEqAbs(
            IERC20(pool).balanceOf(bob),
            erc4626PoolInitialAmount * 2 - BUFFER_MINIMUM_TOTAL_SUPPLY,
            errorTolerance,
            "Wrong yield-bearing pool BPT amount"
        );

        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(pool);
        // The yield-bearing pool should have `erc4626PoolInitialAmount` of both tokens.
        assertEq(address(tokens[waDaiIdx]), address(waDAI), "Wrong yield-bearing pool token (waDAI)");
        assertEq(address(tokens[waWethIdx]), address(waWETH), "Wrong yield-bearing pool token (waWETH)");
        assertEq(
            balancesRaw[waDaiIdx],
            _vaultPreviewDeposit(waDAI, erc4626PoolInitialAmount),
            "Wrong yield-bearing pool balance waDAI"
        );
        assertEq(
            balancesRaw[waWethIdx],
            _vaultPreviewDeposit(waWETH, erc4626PoolInitialAmount),
            "Wrong yield-bearing pool balance waWETH"
        );

        // LP should have correct amount of shares from buffer (invested amount in underlying minus burned "BPTs").
        uint256 waDAIInvariantDelta = bufferInitialAmount +
            waDAI.previewRedeem(waDAI.previewDeposit(bufferInitialAmount));
        assertEq(
            vault.getBufferOwnerShares(IERC4626(waDAI), lp),
            waDAIInvariantDelta - BUFFER_MINIMUM_TOTAL_SUPPLY,
            "Wrong share of waDAI buffer belonging to LP"
        );
        assertEq(
            vault.getBufferTotalShares(IERC4626(waDAI)),
            waDAIInvariantDelta,
            "Wrong issued shares of waDAI buffer"
        );

        uint256 waWETHInvariantDelta = bufferInitialAmount +
            waWETH.previewRedeem(waWETH.previewDeposit(bufferInitialAmount));
        assertEq(
            vault.getBufferOwnerShares(IERC4626(waWETH), lp),
            waWETHInvariantDelta - BUFFER_MINIMUM_TOTAL_SUPPLY,
            "Wrong share of waWETH buffer belonging to LP"
        );
        assertEq(
            vault.getBufferTotalShares(IERC4626(waWETH)),
            waWETHInvariantDelta,
            "Wrong issued shares of waWETH buffer"
        );

        uint256 baseBalance;
        uint256 wrappedBalance;

        // The vault buffers should each have `bufferInitialAmount` of their respective tokens.
        (baseBalance, wrappedBalance) = vault.getBufferBalance(IERC4626(waDAI));
        assertEq(baseBalance, bufferInitialAmount, "Wrong waDAI buffer balance for base token");
        assertEq(
            wrappedBalance,
            waDAI.previewDeposit(bufferInitialAmount),
            "Wrong waDAI buffer balance for wrapped token"
        );

        (baseBalance, wrappedBalance) = vault.getBufferBalance(IERC4626(waWETH));
        assertEq(baseBalance, bufferInitialAmount, "Wrong waWETH buffer balance for base token");
        assertEq(
            wrappedBalance,
            waWETH.previewDeposit(bufferInitialAmount),
            "Wrong waWETH buffer balance for wrapped token"
        );
    }

    function _initializeBuffers() private {
        // Create and fund buffer pools.
        uint256 waDAILPShares = waDAI.previewDeposit(bufferInitialAmount);
        uint256 waUSDCLPShares = waUSDC.previewDeposit(bufferInitialAmount);
        uint256 waWETHLPShares = waWETH.previewDeposit(bufferInitialAmount);

        vm.startPrank(lp);
        bufferRouter.initializeBuffer(waDAI, bufferInitialAmount, waDAILPShares, 0);
        bufferRouter.initializeBuffer(waUSDC, bufferInitialAmount, waUSDCLPShares, 0);
        bufferRouter.initializeBuffer(waWETH, bufferInitialAmount, waWETHLPShares, 0);
        vm.stopPrank();
    }
}
