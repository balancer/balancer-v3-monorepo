// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { PoolConfigBits, PoolConfigLib } from "../../contracts/lib/PoolConfigLib.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract DynamicFeePoolTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    address internal noFeeReferencePool;
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        defaultBalance = 1e10 * 1e18;
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");
    }

    function createPool() internal virtual override returns (address) {
        address[] memory tokens = [address(dai), address(usdc)].toMemoryArray();

        noFeeReferencePool = _createPool(tokens, "noFeeReferencePool");

        return _createPool(tokens, "swapPool");
    }

    function _createPool(address[] memory tokens, string memory label) internal virtual override returns (address) {
        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");
        vm.label(address(newPool), label);
        PoolRoleAccounts memory roleAccounts;
        PoolHooks memory poolHooks;

        poolHooks.shouldCallComputeDynamicSwapFee = true;

        factoryMock.registerPool(
            address(newPool),
            vault.buildTokenConfig(tokens.asIERC20()),
            roleAccounts,
            poolHooks,
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: true,
                enableRemoveLiquidityCustom: true
            })
        );

        return address(newPool);
    }

    function initPool() internal override {
        poolInitAmount = 1e9 * 1e18;

        vm.startPrank(lp);
        _initPool(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(noFeeReferencePool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    function testSwapCallsComputeFee() public {
        IBasePool.PoolSwapParams memory poolSwapParams = IBasePool.PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: defaultAmount,
            balancesScaled18: [poolInitAmount, poolInitAmount].toMemoryArray(),
            indexIn: daiIdx,
            indexOut: usdcIdx,
            router: address(router),
            user: alice,
            userData: bytes("")
        });

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(PoolMock.onComputeDynamicSwapFee.selector, poolSwapParams),
            1 // callCount
        );

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(PoolMock.onSwap.selector, poolSwapParams),
            1 // callCount
        );

        vm.prank(alice);
        // Perform a swap in the pool
        uint256 swapAmountOut = router.swapSingleTokenExactIn(
            address(pool),
            dai,
            usdc,
            defaultAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function testExternalComputeFee() public {
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(PoolMock.onComputeDynamicSwapFee.selector),
            1 // callCount
        );

        IBasePool.PoolSwapParams memory swapParams;
        uint256 dynamicSwapFeePercentage = 0.01e18;

        PoolMock(pool).setDynamicSwapFeePercentage(dynamicSwapFeePercentage);

        (bool success, uint256 actualDynamicSwapFee) = vault.computeDynamicSwapFee(address(pool), swapParams);

        assertTrue(success, "computeDynamicSwapFee returned false");
        assertEq(actualDynamicSwapFee, dynamicSwapFeePercentage, "Wrong dynamicSwapFeePercentage");
    }

    function testSwapChargesFees__Fuzz(uint256 dynamicSwapFeePercentage) public {
        dynamicSwapFeePercentage = bound(dynamicSwapFeePercentage, 0, 1e18);
        PoolMock(pool).setDynamicSwapFeePercentage(dynamicSwapFeePercentage);

        vm.prank(alice);
        uint256 swapAmountOut = router.swapSingleTokenExactIn(
            address(pool),
            dai,
            usdc,
            defaultAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        PoolMock(noFeeReferencePool).setDynamicSwapFeePercentage(0);

        vm.prank(bob);
        uint256 liquidityAmountOut = router.swapSingleTokenExactIn(
            address(noFeeReferencePool),
            dai,
            usdc,
            defaultAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assertEq(
            swapAmountOut,
            liquidityAmountOut.mulDown(dynamicSwapFeePercentage.complement()),
            "Swap and liquidity amounts are not correct"
        );
    }
}
