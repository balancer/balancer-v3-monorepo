// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiToken.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { PoolMock } from "../../../../contracts/test/PoolMock.sol";
import { Router } from "../../../../contracts/Router.sol";
import { RouterCommon } from "../../../../contracts/RouterCommon.sol";
import { VaultMock } from "../../../../contracts/test/VaultMock.sol";
import { VaultExtensionMock } from "../../../../contracts/test/VaultExtensionMock.sol";

import { VaultMockDeployer } from "../../utils/VaultMockDeployer.sol";

import { BaseVaultTest } from "../../utils/BaseVaultTest.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {
    AddLiquidityKind,
    RemoveLiquidityKind,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

contract RouterMutationTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal usdcAmountIn = 1e3 * 1e6;
    uint256 internal daiAmountIn = 1e3 * 1e18;
    uint256 internal daiAmountOut = 1e2 * 1e18;
    uint256 internal ethAmountIn = 1e3 ether;
    uint256 internal initBpt = 10e18;
    uint256 internal bptAmountOut = 1e18;

    PoolMock internal wethPool;
    PoolMock internal wethPoolNoInit;

    // Track the indices for the local dai/weth pool.
    uint256 internal daiIdxWethPool;
    uint256 internal wethIdx;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    uint256[] internal wethDaiAmountsIn;
    IERC20[] internal wethDaiTokens;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        approveForPool(IERC20(wethPool));
    }

    function createPool() internal override returns (address) {
        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");
        vm.label(address(newPool), "pool");

        factoryMock.registerTestPool(
            address(newPool),
            vault.buildTokenConfig([address(dai), address(usdc)].toMemoryArray().asIERC20()),
            address(lp)
        );
        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        wethPool = new PoolMock(IVault(address(vault)), "ERC20 weth Pool", "ERC20POOL");
        vm.label(address(wethPool), "wethPool");

        factoryMock.registerTestPool(
            address(wethPool),
            vault.buildTokenConfig([address(dai), address(weth)].toMemoryArray().asIERC20()),
            address(lp)
        );

        (daiIdxWethPool, wethIdx) = getSortedIndexes(address(dai), address(weth));

        wethDaiTokens = InputHelpers.sortTokens([address(weth), address(dai)].toMemoryArray().asIERC20());

        wethDaiAmountsIn = new uint256[](2);
        wethDaiAmountsIn[wethIdx] = ethAmountIn;
        wethDaiAmountsIn[daiIdxWethPool] = daiAmountIn;

        wethPoolNoInit = new PoolMock(IVault(address(vault)), "ERC20 weth Pool", "ERC20POOL");
        vm.label(address(wethPoolNoInit), "wethPoolNoInit");

        factoryMock.registerTestPool(
            address(wethPoolNoInit),
            vault.buildTokenConfig([address(weth), address(dai)].toMemoryArray().asIERC20()),
            address(lp)
        );

        return address(newPool);
    }

    function initPool() internal override {
        (TokenConfig[] memory tokenConfig, , ) = vault.getPoolTokenInfo(address(pool));
        vm.prank(lp);
        IERC20[] memory tokens = new IERC20[](tokenConfig.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i] = tokenConfig[i].token;
        }

        router.initialize(address(pool), tokens, [poolInitAmount, poolInitAmount].toMemoryArray(), 0, false, "");

        vm.prank(lp);
        bool wethIsEth = true;
        router.initialize{ value: ethAmountIn }(
            address(wethPool),
            wethDaiTokens,
            wethDaiAmountsIn,
            initBpt,
            wethIsEth,
            bytes("")
        );
    }

    /*
        initializeHook
            [x] onlyVault
            [] nonReentrant
        TODO: Missing reentrancy
    */
    function testInitializeHookWhenNotVault() public {
        createPool();

        IRouter.InitializeHookParams memory hookParams = IRouter.InitializeHookParams(
            msg.sender,
            address(wethPool),
            wethDaiTokens,
            wethDaiAmountsIn,
            0,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        router.initializeHook(hookParams);
    }

    /*
        addLiquidityHook
            [x] onlyVault
            [] nonReentrant
    */
    function testAddLiquidityHookWhenNotVault() public {
        createPool();

        IRouter.AddLiquidityHookParams memory hookParams = IRouter.AddLiquidityHookParams(
            msg.sender,
            address(wethPool),
            wethDaiAmountsIn,
            0,
            AddLiquidityKind.PROPORTIONAL,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        router.addLiquidityHook(hookParams);
    }

    /*
        removeLiquidityRecoveryHook
            [x] onlyVault
            [] nonReentrant
        TODO: Missing reentrancy
    */
    function testRemoveLiquidityRecoveryHookWhenNotVault() public {
        createPool();

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        router.removeLiquidityRecoveryHook(address(wethPool), msg.sender, wethDaiAmountsIn[0]);
    }

    /*
        swapSingleTokenHook
            [x] onlyVault
            [] nonReentrant
    */
    function testSwapSingleTokenHookWhenNotVault() public {
        address poolAddy = createPool();

        IRouter.SwapSingleTokenHookParams memory params = IRouter.SwapSingleTokenHookParams(
            msg.sender,
            SwapKind.EXACT_IN,
            poolAddy,
            IERC20(dai),
            IERC20(usdc),
            daiAmountIn,
            daiAmountIn,
            block.timestamp + 10,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        router.swapSingleTokenHook(params);
    }

    /*
        querySwapHook
            [x] onlyVault
            [] nonReentrant   
    */
    function testQuerySwapHookWhenNotVault() public {
        address poolAddy = createPool();

        IRouter.SwapSingleTokenHookParams memory params = IRouter.SwapSingleTokenHookParams(
            msg.sender,
            SwapKind.EXACT_IN,
            poolAddy,
            IERC20(dai),
            IERC20(usdc),
            daiAmountIn,
            0,
            block.timestamp + 10,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        router.querySwapHook(params);
    }

    /*
        queryAddLiquidityHook
            [x] onlyVault
            [] nonReentrant        
    */
    function testQueryAddLiquidityHookWhenNotVault() public {
        createPool();

        IRouter.AddLiquidityHookParams memory hookParams = IRouter.AddLiquidityHookParams(
            msg.sender,
            address(wethPool),
            wethDaiAmountsIn,
            0,
            AddLiquidityKind.PROPORTIONAL,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        router.queryAddLiquidityHook(hookParams);
    }

    /*
        queryRemoveLiquidityHook
            [x] onlyVault
            [] nonReentrant        
    */
    function testQueryRemoveLiquidityHookWhenNotVault() public {
        address poolAddy = createPool();

        IRouter.RemoveLiquidityHookParams memory params = IRouter.RemoveLiquidityHookParams(
            msg.sender,
            poolAddy,
            wethDaiAmountsIn,
            0,
            RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        router.queryRemoveLiquidityHook(params);
    }

    /*
        queryRemoveLiquidityRecoveryHook
            [x] onlyVault
            [] nonReentrant    
    */
    function testQueryRemoveLiquidityRecoveryHookWhenNoVault() public {
        address poolAddy = createPool();

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        router.queryRemoveLiquidityRecoveryHook(poolAddy, msg.sender, 10);
    }
}
