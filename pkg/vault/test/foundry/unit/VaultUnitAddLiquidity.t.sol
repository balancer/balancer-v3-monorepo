// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SwapParams,
    SwapLocals,
    PoolData,
    SwapKind,
    VaultState,
    TokenConfig,
    TokenType,
    Rounding
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultUnitAddLiquidityTest is BaseVaultTest {
    using ArrayHelpers for *;
    using ScalingHelpers for *;
    using FixedPoint for *;

    address constant POOL = address(0x1234);
    IERC20 constant TOKEN_IN = IERC20(address(0x2345));
    IERC20 constant TOKEN_OUT = IERC20(address(0x3456));

    uint256[] initialBalances = [uint256(10 ether), 10 ether];
    uint256[] decimalScalingFactors = [uint256(1e18), 1e18];
    uint256[] tokenRates = [uint256(1e18), 2e18];

    uint256 amountGivenRaw = 1 ether;
    uint256 mockedAmountCalculatedScaled18 = 5e17;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testAddLiquidityProportional() public {
        PoolData memory poolData;
        // poolData.tokenConfig.length;
        // params.kind
        // params.minBptAmountOut;
        //  poolData.balancesLiveScaled18,
        // _totalSupply(params.pool),
        // params.minBptAmountOut
        // poolData.tokenConfig[i].token;
        //  _computeAndChargeProtocolFees(
        //     poolData,
        //     swapFeeAmountsScaled18[i],
        //     vaultState.protocolSwapFeePercentage,
        //     params.pool,
        //     token,
        //     i
        // );
        //  poolData.decimalScalingFactors[i],
        // poolData.tokenRates[i]
        // params.maxAmountsIn[i]
        // _setPoolBalances(params.pool, poolData);
        //  _mint(address(params.pool), params.to, bptAmountOut);
        // emit PoolBalanceChanged(params.pool, params.to, tokens, amountsInRaw.unsafeCastToInt256(true));
    }
}
