// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { E2eBatchSwapTest } from "@balancer-labs/v3-vault/test/foundry/E2eBatchSwap.t.sol";

import { Gyro2ClpPoolDeployer } from "./utils/Gyro2ClpPoolDeployer.sol";

contract E2eBatchSwapGyro2CLPTest is E2eBatchSwapTest, Gyro2ClpPoolDeployer {
    /// @notice Overrides BaseVaultTest _createPool(). This pool is used by E2eBatchSwapTest tests.
    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address, bytes memory) {
        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);
        return createGyro2ClpPool(tokens, rateProviders, label, vault, lp);
    }

    function _setUpVariables() internal override {
        tokenA = dai;
        tokenB = usdc;
        tokenC = ERC20TestToken(address(weth));
        tokenD = wsteth;
        sender = lp;
        poolCreator = lp;

        // If there are swap fees, the amountCalculated may be lower than MIN_TRADE_AMOUNT. So, multiplying
        // MIN_TRADE_AMOUNT by 10 creates a margin.
        minSwapAmountTokenA = 10 * PRODUCTION_MIN_TRADE_AMOUNT;
        minSwapAmountTokenD = 10 * PRODUCTION_MIN_TRADE_AMOUNT;

        // Divide init amount by 10 to make sure weighted math ratios are respected (Cannot trade more than 30% of pool
        // balance).
        maxSwapAmountTokenA = poolInitAmount() / 10;
        maxSwapAmountTokenD = poolInitAmount() / 10;
    }
}
