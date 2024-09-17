// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";

import { RouterMock } from "../../../../contracts/test/RouterMock.sol";

contract OperationsHandler is Test {
    uint256 internal constant MAX_UINT128 = type(uint128).max;

    // Vault mock.
    IVaultMock internal vault;
    // Router mock.
    RouterMock internal router;
    // Alice - Sender of swap operations.
    address internal alice;
    // Pool for tests.
    address internal pool;

    IERC20 internal dai;
    IERC20 internal usdc;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    constructor(
        IVaultMock vaultMock,
        RouterMock routerMock,
        address aliceAddress,
        address poolAddress,
        IERC20 daiToken,
        IERC20 usdcToken,
        uint256 newDaiIdx,
        uint256 newUsdcIdx
    ) {
        vault = vaultMock;
        router = routerMock;
        alice = aliceAddress;
        pool = poolAddress;

        dai = daiToken;
        usdc = usdcToken;
        daiIdx = newDaiIdx;
        usdcIdx = newUsdcIdx;
    }

    function executeSwapDaiExactIn(uint256 exactDaiAmountIn) public {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(pool);
        console.log("Swap DAI -> USDC - Exact In");
        exactDaiAmountIn = bound(exactDaiAmountIn, 1, balancesRaw[daiIdx]);

        vm.startPrank(alice);
        router.swapSingleTokenExactIn(pool, dai, usdc, exactDaiAmountIn, 0, MAX_UINT128, false, bytes(""));
        vm.stopPrank();
    }

    function executeSwapUsdcExactIn(uint256 exactUsdcAmountIn) public {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(pool);
        console.log("Swap USDC -> DAI - Exact In");
        exactUsdcAmountIn = bound(exactUsdcAmountIn, 1, balancesRaw[usdcIdx]);

        vm.startPrank(alice);
        router.swapSingleTokenExactIn(pool, usdc, dai, exactUsdcAmountIn, 0, MAX_UINT128, false, bytes(""));
        vm.stopPrank();
    }

    function executeSwapDaiExactOut(uint256 exactDaiAmountOut) public {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(pool);
        console.log("Swap USDC -> DAI - Exact Out");
        exactDaiAmountOut = bound(exactDaiAmountOut, 1, balancesRaw[daiIdx]);

        vm.startPrank(alice);
        router.swapSingleTokenExactOut(pool, usdc, dai, exactDaiAmountOut, MAX_UINT128, MAX_UINT128, false, bytes(""));
        vm.stopPrank();
    }

    function executeSwapUsdcExactOut(uint256 exactUsdcAmountOut) public {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(pool);
        console.log("Swap DAI -> USDC - Exact Out");
        exactUsdcAmountOut = bound(exactUsdcAmountOut, 1, balancesRaw[usdcIdx]);

        vm.startPrank(alice);
        router.swapSingleTokenExactOut(pool, dai, usdc, exactUsdcAmountOut, MAX_UINT128, MAX_UINT128, false, bytes(""));
        vm.stopPrank();
    }
}
