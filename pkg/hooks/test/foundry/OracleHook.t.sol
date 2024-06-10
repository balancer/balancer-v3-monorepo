// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";

import { OracleHook } from "../../contracts/OracleHook.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

contract HooksTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // Another pool to test hook onRegister
    address internal anotherPool;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        // Create another pool to test onRegister
        anotherPool = address(new PoolMock(IVault(address(vault)), "Another Pool", "ANOTHER"));
        vm.label(anotherPool, "another pool");
    }

    function createHook() internal override returns (address) {
        return address(new OracleHook(IVault(address(vault))));
    }

    // on register

    function testOnRegisterMoreThanTwoTokensRevert() public {
        PoolRoleAccounts memory roleAccounts;
        LiquidityManagement memory liquidityManagement;

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc), address(weth)].toMemoryArray().asIERC20()
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.HookRegistrationFailed.selector,
                poolHooksContract,
                anotherPool,
                address(factoryMock)
            )
        );
        factoryMock.registerPool(anotherPool, tokenConfig, roleAccounts, poolHooksContract, liquidityManagement);
    }

    function testOnRegisterTwoTokens() public {
        PoolRoleAccounts memory roleAccounts;
        LiquidityManagement memory liquidityManagement;

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        vm.expectCall(
            poolHooksContract,
            abi.encodeWithSelector(
                IHooks.onRegister.selector,
                address(factoryMock),
                anotherPool,
                tokenConfig,
                liquidityManagement
            )
        );
        factoryMock.registerPool(anotherPool, tokenConfig, roleAccounts, poolHooksContract, liquidityManagement);
    }

    // before swap

    function testOnBeforeSwapHook() public {
        vm.prank(bob);
        vm.expectCall(
            poolHooksContract,
            abi.encodeWithSelector(
                IHooks.onBeforeSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: SwapKind.EXACT_IN,
                    amountGivenScaled18: defaultAmount,
                    balancesScaled18: [defaultAmount, defaultAmount].toMemoryArray(),
                    indexIn: usdcIdx,
                    indexOut: daiIdx,
                    router: address(router),
                    userData: ""
                })
            )
        );
        snapStart("swapWithOnBeforeSwapHook");
        router.swapSingleTokenExactIn(pool, usdc, dai, defaultAmount, 0, MAX_UINT256, false, "");
        snapEnd();
    }

    // after swap

    function testOnAfterSwapHook() public {
        setSwapFeePercentage(swapFeePercentage);
        vault.manualSetAggregateProtocolSwapFeePercentage(
            pool,
            _getAggregateFeePercentage(protocolSwapFeePercentage, 0)
        );

        uint256 expectedAmountOut = defaultAmount.mulDown(swapFeePercentage.complement());
        uint256 swapFee = defaultAmount.mulDown(swapFeePercentage);
        uint256 protocolFee = swapFee.mulDown(protocolSwapFeePercentage);

        vm.prank(bob);
        vm.expectCall(
            poolHooksContract,
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                IHooks.AfterSwapParams({
                    kind: SwapKind.EXACT_IN,
                    tokenIn: usdc,
                    tokenOut: dai,
                    amountInScaled18: defaultAmount,
                    amountOutScaled18: expectedAmountOut,
                    tokenInBalanceScaled18: defaultAmount * 2,
                    tokenOutBalanceScaled18: defaultAmount - expectedAmountOut - protocolFee,
                    router: address(router),
                    userData: ""
                }),
                expectedAmountOut
            )
        );
        snapStart("swapWithOnAfterSwapHook");
        router.swapSingleTokenExactIn(pool, usdc, dai, defaultAmount, 0, MAX_UINT256, false, "");
        snapEnd();
    }
}
