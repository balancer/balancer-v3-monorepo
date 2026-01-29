// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { E2eErc4626SwapsTest } from "@balancer-labs/v3-vault/test/foundry/E2eErc4626Swaps.t.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";

import { StablePoolContractsDeployer } from "./utils/StablePoolContractsDeployer.sol";
import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";

contract E2eErc4626SwapsStableTest is E2eErc4626SwapsTest, StablePoolContractsDeployer {
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    string internal constant POOL_VERSION = "Pool v1";
    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%
    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    function createPoolFactory() internal override returns (address) {
        return address(deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", POOL_VERSION));
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC4626 Stable Pool";
        string memory symbol = "STABLE";

        // Gets the tokenConfig from BaseERC4626BufferTest (it means, waDAI and waUSDC with rate providers).
        TokenConfig[] memory tokenConfig = getTokenConfig();

        PoolRoleAccounts memory roleAccounts;

        // Allow pools created by `factory` to use poolHooksMock hooks.
        PoolHooksMock(poolHooksContract).allowFactory(poolFactory);

        newPool = StablePoolFactory(poolFactory).create(
            name,
            symbol,
            tokenConfig,
            DEFAULT_AMP_FACTOR,
            roleAccounts,
            DEFAULT_SWAP_FEE,
            poolHooksContract,
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );
        vm.label(address(newPool), name);

        // Cannot set the pool creator directly on a standard Balancer stable pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        poolArgs = abi.encode(
            StablePool.NewPoolParams({
                name: name,
                symbol: symbol,
                amplificationParameter: DEFAULT_AMP_FACTOR,
                version: POOL_VERSION
            }),
            vault
        );
    }

    /// @dev Override to set tighter bounds on initial balances to prevent reverts (max imbalance exceeded).
    function _setPoolBalances(uint256 liquidityWaDai, uint256 liquidityWaWeth) internal virtual override {
        // 1% to 65x of erc4626 initial pool liquidity.
        liquidityWaDai = bound(
            liquidityWaDai,
            erc4626PoolInitialAmount.mulDown(1e16),
            erc4626PoolInitialAmount.mulDown(65e18)
        );
        liquidityWaDai = _vaultPreviewDeposit(waDAI, liquidityWaDai);
        // 1% to 65x of erc4626 initial pool liquidity.
        liquidityWaWeth = bound(
            liquidityWaWeth,
            erc4626PoolInitialAmount.mulDown(1e16),
            erc4626PoolInitialAmount.mulDown(65e18)
        );
        liquidityWaWeth = _vaultPreviewDeposit(waWETH, liquidityWaWeth);

        uint256[] memory newPoolBalance = new uint256[](2);
        newPoolBalance[waDaiIdx] = liquidityWaDai;
        newPoolBalance[waWethIdx] = liquidityWaWeth;

        uint256[] memory newPoolBalanceLiveScaled18 = new uint256[](2);
        newPoolBalanceLiveScaled18[waDaiIdx] = liquidityWaDai.toScaled18ApplyRateRoundUp(1, waDAI.getRate());
        newPoolBalanceLiveScaled18[waWethIdx] = liquidityWaWeth.toScaled18ApplyRateRoundUp(1, waWETH.getRate());

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalanceLiveScaled18);
        // Updates pool data with latest token rates.
        vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_DOWN);
    }
}
