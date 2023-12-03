// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";

import { ERC20PoolMock } from "../../contracts/test/ERC20PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { PoolConfigLib } from "../../contracts/lib/PoolConfigLib.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

contract VaultSwapTest is Test {
    using AssetHelpers for address;
    using AssetHelpers for address[];
    using AssetHelpers for address[];
    using ArrayHelpers for address[2];
    using ArrayHelpers for uint256[2];

    VaultMock vault;
    Router router;
    BasicAuthorizerMock authorizer;
    ERC20PoolMock pool;
    ERC20PoolMock adaiPool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    ERC20TestToken aDAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant USDC_AMOUNT_IN = 1e3 * 1e6;
    uint256 constant ADAI_AMOUNT_IN = 1e3 * 1e18;
    uint256 constant DAI_AMOUNT_IN = 1e3 * 1e18;
    uint256 constant USDC_SCALING = 1e12; // 18 - 6
    uint256 initialBptSupply;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), address(0));
        USDC = new ERC20TestToken("USDC", "USDC", 6);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        aDAI = new ERC20TestToken("aDAI", "aDAI", 18);
        IRateProvider[] memory rateProviders = new IRateProvider[](2);

        pool = new ERC20PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );

        // Pool with all 18-decimals
        adaiPool = new ERC20PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(aDAI)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );

        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallAfterSwap = true;
        vault.setConfig(address(pool), config);

        USDC.mint(bob, USDC_AMOUNT_IN);
        DAI.mint(bob, DAI_AMOUNT_IN);
        aDAI.mint(bob, ADAI_AMOUNT_IN);

        USDC.mint(alice, USDC_AMOUNT_IN);
        DAI.mint(alice, DAI_AMOUNT_IN * 2);
        aDAI.mint(alice, ADAI_AMOUNT_IN);

        vm.startPrank(bob);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);
        aDAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.startPrank(alice);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);
        aDAI.approve(address(vault), type(uint256).max);

        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            [DAI_AMOUNT_IN, USDC_AMOUNT_IN].toMemoryArray(),
            0,
            bytes("")
        );
        initialBptSupply = IERC20(pool).totalSupply();

        router.initialize(
            address(adaiPool),
            [address(DAI), address(aDAI)].toMemoryArray().asAsset(),
            [DAI_AMOUNT_IN, ADAI_AMOUNT_IN].toMemoryArray(),
            0,
            bytes("")
        );

        vm.stopPrank();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(address(USDC), "USDC");
        vm.label(address(DAI), "DAI");
        vm.label(address(aDAI), "aDAI");
    }

    function testOnAfterSwapCallback() public {
        // Calls `onSwap` in the pool.
        vm.prank(bob);
        // Balances are scaled to 18 decimals; DAI already has 18.
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.SwapParams({
                    kind: IVault.SwapKind.GIVEN_IN,
                    tokenIn: IERC20(USDC),
                    tokenOut: IERC20(DAI),
                    amountGivenScaled18: USDC_AMOUNT_IN * USDC_SCALING,
                    balancesScaled18: [DAI_AMOUNT_IN, USDC_AMOUNT_IN * USDC_SCALING].toMemoryArray(),
                    indexIn: 1,
                    indexOut: 0,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            USDC_AMOUNT_IN,
            0,
            type(uint256).max,
            bytes("")
        );
    }

    function testOnAfterSwapCallbackRevert() public {
        // should fail
        pool.setFailOnAfterSwapCallback(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVault.CallbackFailed.selector));
        router.swap(
            IVault.SwapKind.GIVEN_IN,
            address(pool),
            address(USDC).asAsset(),
            address(DAI).asAsset(),
            USDC_AMOUNT_IN,
            DAI_AMOUNT_IN,
            type(uint256).max,
            bytes("")
        );
    }

    // Before add

    /// forge-config: default.fuzz.runs = 32
    function testOnBeforeAddLiquidityFlag(uint8 kindUint) public {
        IVault.AddLiquidityKind kind = IVault.AddLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.AddLiquidityKind).max))
        );
        pool.setFailOnBeforeAddLiquidityCallback(true);

        vm.prank(bob);
        // Doesn't fail, does not call callbacks
        router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            _getSuitableMaxInputs(kind),
            initialBptSupply,
            kind,
            bytes("")
        );
    }

    /// forge-config: default.fuzz.runs = 32
    function testOnBeforeAddLiquidityCallback(uint8 kindUint) public {
        IVault.AddLiquidityKind kind = IVault.AddLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.AddLiquidityKind).max))
        );
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeAddLiquidity = true;
        vault.setConfig(address(pool), config);

        (, uint256[] memory poolBalances, , ) = vault.getPoolTokenInfo(address(pool));
        uint256[] memory maxInputs = _getSuitableMaxInputs(kind);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onBeforeAddLiquidity.selector,
                bob,
                [maxInputs[0], maxInputs[1] * USDC_SCALING].toMemoryArray(),
                initialBptSupply,
                [poolBalances[0], poolBalances[1] * USDC_SCALING].toMemoryArray(),
                bytes("")
            )
        );
        router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            maxInputs,
            initialBptSupply,
            kind,
            bytes("")
        );
    }

    // Before remove

    /// forge-config: default.fuzz.runs = 32
    function testOnBeforeRemoveLiquidityFlag(uint8 kindUint) public {
        IVault.RemoveLiquidityKind kind = IVault.RemoveLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.RemoveLiquidityKind).max))
        );
        pool.setFailOnBeforeRemoveLiquidityCallback(true);

        uint256 bptBalance = pool.balanceOf(alice);
        // Alice has LP tokens from initialization
        vm.prank(alice);
        // Doesn't fail, does not call callbacks
        router.removeLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            bptBalance,
            _getSuitableMinOutputs(kind),
            kind,
            bytes("")
        );
    }

    /// forge-config: default.fuzz.runs = 32
    function testOnBeforeRemoveLiquidityCallback(uint8 kindUint) public {
        IVault.RemoveLiquidityKind kind = IVault.RemoveLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.RemoveLiquidityKind).max))
        );
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeRemoveLiquidity = true;
        vault.setConfig(address(pool), config);

        (, uint256[] memory poolBalances, , ) = vault.getPoolTokenInfo(address(pool));
        uint256[] memory minOutputs = _getSuitableMinOutputs(kind);

        // Alice has LP tokens from initialization
        uint256 bptBalance = pool.balanceOf(alice);
        vm.prank(alice);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onBeforeRemoveLiquidity.selector,
                alice,
                bptBalance,
                [minOutputs[0], minOutputs[1] * USDC_SCALING].toMemoryArray(),
                [poolBalances[0], poolBalances[1] * USDC_SCALING].toMemoryArray(),
                bytes("")
            )
        );
        router.removeLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            bptBalance,
            _getSuitableMinOutputs(kind),
            kind,
            bytes("")
        );
    }

    // After add

    /// forge-config: default.fuzz.runs = 32
    function testOnAfterAddLiquidityFlag(uint8 kindUint) public {
        IVault.AddLiquidityKind kind = IVault.AddLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.AddLiquidityKind).max))
        );
        pool.setFailOnAfterAddLiquidityCallback(true);

        vm.prank(bob);
        // Doesn't fail, does not call callbacks
        router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            _getSuitableMaxInputs(kind),
            initialBptSupply,
            kind,
            bytes("")
        );
    }

    /// forge-config: default.fuzz.runs = 32
    function testOnAfterAddLiquidityCallback(uint8 kindUint) public {
        IVault.AddLiquidityKind kind = IVault.AddLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.AddLiquidityKind).max))
        );
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallAfterAddLiquidity = true;
        vault.setConfig(address(pool), config);

        (, uint256[] memory poolBalances, , ) = vault.getPoolTokenInfo(address(pool));
        uint256[] memory amountsIn;
        uint256 bptAmountOut;

        // Dry run to get actual amounts in and bpt out from the operation
        uint256 snapshot = vm.snapshot();
        vm.prank(bob);
        (amountsIn, bptAmountOut, ) = router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            _getSuitableMaxInputs(kind),
            initialBptSupply,
            kind,
            bytes("")
        );
        vm.revertTo(snapshot);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onAfterAddLiquidity.selector,
                bob,
                [amountsIn[0], amountsIn[1] * USDC_SCALING].toMemoryArray(),
                bptAmountOut,
                [poolBalances[0] + amountsIn[0], (poolBalances[1] + amountsIn[1]) * USDC_SCALING].toMemoryArray(),
                bytes("")
            )
        );
        router.addLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            _getSuitableMaxInputs(kind),
            initialBptSupply,
            kind,
            bytes("")
        );
    }

    // After remove

    /// forge-config: default.fuzz.runs = 32
    function testOnAfterRemoveLiquidityFlag(uint8 kindUint) public {
        IVault.RemoveLiquidityKind kind = IVault.RemoveLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.RemoveLiquidityKind).max))
        );
        pool.setFailOnAfterRemoveLiquidityCallback(true);

        uint256 bptBalance = pool.balanceOf(alice);
        // Alice has LP tokens from initialization
        vm.prank(alice);
        // Doesn't fail, does not call callbacks
        router.removeLiquidity(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asAsset(),
            bptBalance,
            _getSuitableMinOutputs(kind),
            kind,
            bytes("")
        );
    }

    /// forge-config: default.fuzz.runs = 32
    function testOnAfterRemoveLiquidityCallback(uint8 kindUint) public {
        IVault.RemoveLiquidityKind kind = IVault.RemoveLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.RemoveLiquidityKind).max))
        );
        PoolConfig memory config = vault.getPoolConfig(address(adaiPool));
        config.callbacks.shouldCallAfterRemoveLiquidity = true;
        vault.setConfig(address(adaiPool), config);

        uint256 bptBalance = adaiPool.balanceOf(alice);
        (, uint256[] memory poolBalances, , ) = vault.getPoolTokenInfo(address(adaiPool));
        uint256 bptAmountIn;
        uint256[] memory amountsOut;

        // Dry run to get actual amounts out and bpt in from the operation
        uint256 snapshot = vm.snapshot();
        // Alice has LP tokens from initialization
        vm.prank(alice);
        (bptAmountIn, amountsOut, ) = router.removeLiquidity(
            address(adaiPool),
            [address(DAI), address(aDAI)].toMemoryArray().asAsset(),
            bptBalance,
            _getSuitableMinOutputs(kind),
            kind,
            bytes("")
        );
        vm.revertTo(snapshot);

        vm.prank(alice);
        vm.expectCall(
            address(adaiPool),
            abi.encodeWithSelector(
                IBasePool.onAfterRemoveLiquidity.selector,
                alice,
                bptAmountIn,
                [amountsOut[0], amountsOut[1]].toMemoryArray(),
                [poolBalances[0] - amountsOut[0], poolBalances[1] - amountsOut[1]].toMemoryArray(),
                bytes("")
            )
        );
        router.removeLiquidity(
            address(adaiPool),
            [address(DAI), address(aDAI)].toMemoryArray().asAsset(),
            bptBalance,
            _getSuitableMinOutputs(kind),
            kind,
            bytes("")
        );
    }

    // Helpers

    function _getSuitableMaxInputs(IVault.AddLiquidityKind kind) internal pure returns (uint256[] memory maxInputs) {
        if (kind == IVault.AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            maxInputs = [DAI_AMOUNT_IN, uint256(0)].toMemoryArray();
        } else {
            maxInputs = [DAI_AMOUNT_IN, USDC_AMOUNT_IN].toMemoryArray();
        }
    }

    function _getSuitableMinOutputs(
        IVault.RemoveLiquidityKind kind
    ) internal pure returns (uint256[] memory minOutputs) {
        if (
            kind == IVault.RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN ||
            kind == IVault.RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT
        ) {
            minOutputs = [DAI_AMOUNT_IN, uint256(0)].toMemoryArray();
        } else {
            // In proportional it's not possible to extract all the tokens given that some BPT is sent to address(0).
            minOutputs = [DAI_AMOUNT_IN / 10, USDC_AMOUNT_IN / 10].toMemoryArray();
        }
    }
}
