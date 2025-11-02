// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { TokenConfig, PoolRoleAccounts, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";
import { RouterMock } from "@balancer-labs/v3-vault/contracts/test/RouterMock.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { SwapFeeMinimizer } from "../../contracts/SwapFeeMinimizer/SwapFeeMinimizer.sol";
import {
    SwapFeeMinimizerFactory,
    PoolCreationParams,
    MinimizerParams
} from "../../contracts/SwapFeeMinimizer/SwapFeeMinimizerFactory.sol";

contract SwapFeeMinimizerFactoryTest is BaseVaultTest {
    SwapFeeMinimizerFactory factory;
    WeightedPoolFactory weightedPoolFactory;

    address poolOwner = makeAddr("poolOwner");
    address swapUser = makeAddr("swapUser");

    uint256 constant MIN_SWAP_FEE = 0.001e16; // 0.001%
    uint256 constant NORMAL_SWAP_FEE = 0.01e16; // 0.01%

    string poolName = "Test Pool";
    string poolSymbol = "TEST";
    IERC20 outputToken;

    function setUp() public override {
        super.setUp();

        factory = new SwapFeeMinimizerFactory(router, vault, permit2);

        // Deploy weighted pool factory
        weightedPoolFactory = new WeightedPoolFactory(
            vault,
            365 days, // pauseWindowDuration
            "Factory v1", // factoryVersion
            "Pool v1" // poolVersion
        );

        outputToken = dai; // Tests will minimize fees w/ DAI as outputToken
    }

    function _createPoolParams() internal view returns (PoolCreationParams memory) {
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0] = TokenConfig({
            token: dai,
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        tokens[1] = TokenConfig({
            token: usdc,
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });

        // 50/50 pool
        uint256[] memory weights = new uint256[](2);
        weights[0] = 50e16;
        weights[1] = 50e16;

        return
            PoolCreationParams({
                name: poolName,
                symbol: poolSymbol,
                tokens: tokens,
                normalizedWeights: weights,
                swapFeePercentage: NORMAL_SWAP_FEE,
                poolHooksContract: address(0),
                enableDonation: false,
                disableUnbalancedLiquidity: false
            });
    }

    function _createMinimizerParams(address owner, uint256 minFee) internal view returns (MinimizerParams memory) {
        IERC20[] memory inputTokens = new IERC20[](1);
        inputTokens[0] = usdc;

        return
            MinimizerParams({
                inputTokens: inputTokens,
                outputToken: outputToken,
                initialOwner: owner,
                minimalFee: minFee
            });
    }

    function testConstructor() public view {
        assertEq(address(factory.router()), address(router));
        assertEq(address(factory.vault()), address(vault));
    }

    function testDeployWeightedPoolWithMinimizer() public {
        bytes32 salt = keccak256("test");

        // Deploy pool with minimizer
        (address pool, SwapFeeMinimizer minimizer) = factory.deployWeightedPoolWithMinimizer(
            _createPoolParams(),
            _createMinimizerParams(poolOwner, MIN_SWAP_FEE),
            weightedPoolFactory,
            salt
        );

        // Factory registry
        assertEq(address(factory.feeMinimizers(pool)), address(minimizer));

        // Pool
        assertTrue(pool != address(0));
        assertTrue(pool.code.length > 0);

        // Minimizer
        assertTrue(address(minimizer) != address(0));
        assertEq(minimizer.getPool(), pool);
        assertEq(address(minimizer.getOutputToken()), address(outputToken));
        assertEq(minimizer.getMinimalSwapFee(), MIN_SWAP_FEE);
        assertEq(minimizer.owner(), poolOwner);

        // Minimizer is pool's swap fee manager
        PoolRoleAccounts memory roles = vault.getPoolRoleAccounts(pool);
        assertEq(roles.swapFeeManager, address(minimizer));
    }

    function testDeployWithInvalidMinimalFee() public {
        bytes32 salt = keccak256("test");

        vm.expectRevert();
        factory.deployWeightedPoolWithMinimizer(
            _createPoolParams(),
            _createMinimizerParams(poolOwner, MIN_SWAP_FEE - 1),
            weightedPoolFactory,
            salt
        );
    }

    function testGetCurrentPoolFailsWhenNoPending() public {
        vm.expectRevert(SwapFeeMinimizerFactory.NoPendingPool.selector);
        factory.getCurrentPool();
    }

    function testGetMinimizerForPool() public {
        bytes32 salt = keccak256("test");

        (address pool, SwapFeeMinimizer minimizer) = factory.deployWeightedPoolWithMinimizer(
            _createPoolParams(),
            _createMinimizerParams(poolOwner, MIN_SWAP_FEE),
            weightedPoolFactory,
            salt
        );

        SwapFeeMinimizer retrieved = factory.getMinimizerForPool(pool);
        assertEq(address(retrieved), address(minimizer));
    }

    function testMinimizerViewFunctions() public {
        bytes32 salt = keccak256("test");

        (address pool, SwapFeeMinimizer minimizer) = factory.deployWeightedPoolWithMinimizer(
            _createPoolParams(),
            _createMinimizerParams(poolOwner, MIN_SWAP_FEE),
            weightedPoolFactory,
            salt
        );

        assertEq(address(minimizer.getRouter()), address(router));
        assertEq(address(minimizer.getVault()), address(vault));
        assertEq(minimizer.getPool(), pool);
        assertEq(address(minimizer.getOutputToken()), address(outputToken));
        assertEq(minimizer.getMinimalSwapFee(), MIN_SWAP_FEE);
    }

    function testDeployFailsWithDuplicateTokens() public {
        bytes32 salt = keccak256("duplicate-test");

        TokenConfig[] memory tokens = new TokenConfig[](3);
        tokens[0] = TokenConfig({
            token: dai,
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        tokens[1] = TokenConfig({
            token: usdc,
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        tokens[2] = TokenConfig({
            token: usdc,
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        }); // Duplicate

        uint256[] memory weights = new uint256[](3);
        weights[0] = 33e16; // 33%
        weights[1] = 33e16; // 33%
        weights[2] = 34e16; // 34%

        PoolCreationParams memory poolParams = PoolCreationParams({
            name: poolName,
            symbol: poolSymbol,
            tokens: tokens,
            normalizedWeights: weights,
            swapFeePercentage: NORMAL_SWAP_FEE,
            poolHooksContract: address(0),
            enableDonation: false,
            disableUnbalancedLiquidity: false
        });

        // Fails on deploy
        vm.expectRevert();
        factory.deployWeightedPoolWithMinimizer(
            poolParams,
            _createMinimizerParams(poolOwner, MIN_SWAP_FEE),
            weightedPoolFactory,
            salt
        );
    }
}
