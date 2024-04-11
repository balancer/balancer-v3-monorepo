// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import {
    AddLiquidityKind,
    RemoveLiquidityKind,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {
    WeightedPoolWithHooksFactory
} from "@balancer-labs/v3-pool-with-hooks/contracts/WeightedPoolWithHooksFactory.sol";
import { WeightedPoolWithHooks } from "@balancer-labs/v3-pool-with-hooks/contracts/WeightedPoolWithHooks.sol";
import { BaseHooks } from "@balancer-labs/v3-pool-with-hooks/contracts/BaseHooks.sol";
import { MockHooks } from "@balancer-labs/v3-pool-with-hooks/contracts/test/MockHooks.sol";
import { RouterMock } from "@balancer-labs/v3-vault/contracts/test/RouterMock.sol";
import { VaultMockDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultMockDeployer.sol";
import { DeployPermit2 } from "permit2/test/utils/DeployPermit2.sol";

import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";


import { MyHooks } from "../../contracts/MyHooks.sol";

contract WeightedPoolWithHooksTest is BaseTest, DeployPermit2 {
    using ArrayHelpers for *;

    IPermit2 internal permit2;
    IVaultMock internal vault;
    RouterMock internal router;
    WeightedPoolWithHooksFactory internal poolFactory;
    WeightedPoolWithHooks internal pool;
    BaseHooks internal customHooks;

    string internal constant poolName = "Weighted Pool With Hooks";
    string internal constant poolSymbol = "WeightedPoolWithHooks";
    uint256 internal constant mockSwapFee = 1e16; // 1%

    TokenConfig[] internal tokenConfigs;
    IERC20[] internal erc20Tokens;
    uint256[] internal normalizedWeights;
    bytes internal customHooksBytecode;

    // Mock parameters
    uint256[] internal mockUint256Array = new uint256[](1);
    bytes internal mockBytes = bytes("");
    uint256 internal mockUint256 = 0;
    address internal mockAddress = address(0);
    IBasePool.PoolSwapParams internal mockSwapParams =
        IBasePool.PoolSwapParams(SwapKind.EXACT_IN, 0, mockUint256Array, 0, 0, mockAddress, mockBytes);
    IPoolHooks.AfterSwapParams internal mockAfterSwapParams =
        IPoolHooks.AfterSwapParams(SwapKind.EXACT_IN, IERC20(dai), IERC20(usdc), 0, 0, 0, 0, mockAddress, mockBytes);

    function setUp() public override {
        BaseTest.setUp();

        permit2 = IPermit2(deployPermit2());
        vault = IVaultMock(address(VaultMockDeployer.deploy()));
        poolFactory = new WeightedPoolWithHooksFactory(vault, 365 days);
        router = new RouterMock(IVault(address(vault)), weth, permit2);

        // Default creation parameters
        erc20Tokens.push(IERC20(dai));
        erc20Tokens.push(IERC20(usdc));
        TokenConfig[] memory tokenConfigsMemory = vault.buildTokenConfig(erc20Tokens);
        tokenConfigs.push(tokenConfigsMemory[0]);
        tokenConfigs.push(tokenConfigsMemory[1]);
        normalizedWeights = [uint256(0.50e18), uint256(0.50e18)].toMemoryArray();
        customHooksBytecode = type(MyHooks).creationCode;

        bytes32 salt = bytes32("salt");

        (address poolAddress, address customHooksAddress) = poolFactory.create(
            poolName,
            poolSymbol,
            tokenConfigs,
            normalizedWeights,
            mockSwapFee,
            salt,
            mockAddress,
            customHooksBytecode,
            mockBytes
        );

        pool = WeightedPoolWithHooks(poolAddress);
        customHooks = BaseHooks(customHooksAddress);
    }

    function testMyHook() public {
    }
}
