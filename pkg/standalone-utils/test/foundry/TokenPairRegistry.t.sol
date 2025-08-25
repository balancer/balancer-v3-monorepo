// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { ITokenPairRegistry } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ITokenPairRegistry.sol";
import { SwapPathStep } from "@balancer-labs/v3-interfaces/contracts/vault/BatchRouterTypes.sol";

import { BaseERC4626BufferTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseERC4626BufferTest.sol";

import { TokenPairRegistry } from "../../contracts/TokenPairRegistry.sol";

contract TokenPairRegistryTest is BaseERC4626BufferTest {
    using ArrayHelpers for *;

    TokenPairRegistry internal registry;
    address internal otherPool;

    function setUp() public virtual override {
        super.setUp();
        registry = new TokenPairRegistry(vault, admin);
        (otherPool, ) = createPool();
    }

    function testAddPathPermissioned() external {
        address tokenIn = address(waDAI);
        SwapPathStep[] memory steps;

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        registry.addPath(tokenIn, steps);
    }

    function testAddPathEmpty() external {
        address tokenIn = address(waDAI);
        SwapPathStep[] memory steps;

        vm.prank(admin);
        vm.expectRevert(ITokenPairRegistry.EmptyPath.selector);
        registry.addPath(tokenIn, steps);
    }

    function testAddInvalidPathToken() external {
        address tokenIn = address(waWETH);
        SwapPathStep[] memory steps = new SwapPathStep[](1);

        // Dai is not present in the pool
        steps[0] = SwapPathStep({ pool: address(pool), tokenOut: dai, isBuffer: false });

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ITokenPairRegistry.InvalidSimplePath.selector, pool));
        registry.addPath(tokenIn, steps);

        tokenIn = address(dai);
        // Dai is not present in the pool
        steps[0] = SwapPathStep({ pool: address(pool), tokenOut: waWETH, isBuffer: false });

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ITokenPairRegistry.InvalidSimplePath.selector, pool));
        registry.addPath(tokenIn, steps);
    }

    function testAddPath() external {
        address tokenIn = address(weth);
        address tokenOut = address(dai);
        SwapPathStep[] memory steps = new SwapPathStep[](3);

        steps[0] = SwapPathStep({ pool: address(waWETH), tokenOut: waWETH, isBuffer: true });
        steps[1] = SwapPathStep({ pool: address(pool), tokenOut: waDAI, isBuffer: false });
        steps[2] = SwapPathStep({ pool: address(waDAI), tokenOut: dai, isBuffer: true });

        vm.expectEmit();
        emit ITokenPairRegistry.PathAdded(address(weth), address(dai), 1);

        vm.prank(admin);
        registry.addPath(tokenIn, steps);

        assertEq(registry.getPathCount(tokenIn, tokenOut), 1, "Wrong path count");
        assertEq(registry.getPaths(tokenIn, tokenOut).length, 1, "Paths length does not match count");
        assertEq(registry.getPathAt(tokenIn, tokenOut, 0).length, 3, "Path[0] length does not match steps length");
    }

    function testAddSimplePathPermissioned() external {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        registry.addSimplePath(pool);
    }

    function testAddSimplePathNonRegisteredPoolOrBuffer() external {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ITokenPairRegistry.InvalidSimplePath.selector, address(123)));
        registry.addSimplePath(address(123));
    }

    function testPoolAddSimplePath() external {
        _expectEmitPathAddedEvents(address(waDAI), address(waWETH));

        vm.prank(admin);
        registry.addSimplePath(pool);

        assertEq(registry.getPathCount(address(waWETH), address(waDAI)), 1, "Wrong path count waWETH / waDAI");
        assertEq(registry.getPathCount(address(waDAI), address(waWETH)), 1, "Wrong path count waDAI / waWETH");

        SwapPathStep[][] memory pathsWethDai = registry.getPaths(address(waWETH), address(waDAI));
        assertEq(pathsWethDai.length, 1, "Wrong path length waWETH / waDAI");
        assertEq(pathsWethDai[0].length, 1, "Wrong path[0] waWETH / waDAI steps length");
        assertEq(pathsWethDai[0][0].pool, address(pool), "Wrong path[0] waWETH / waDAI step pool");
        assertEq(address(pathsWethDai[0][0].tokenOut), address(waDAI), "Wrong path[0] waWETH / waDAI token out");
        assertFalse(pathsWethDai[0][0].isBuffer, "Wrong path[0] waWETH / waDAI step isBuffer");

        // getPathAt returns the correct one
        SwapPathStep[] memory pathWethDai0 = registry.getPathAt(address(waWETH), address(waDAI), 0);
        assertEq(
            keccak256(abi.encode(pathWethDai0)),
            keccak256(abi.encode(pathsWethDai[0])),
            "waWETH / waDAI getPathAt mismatch"
        );

        SwapPathStep[][] memory pathsDaiWeth = registry.getPaths(address(waDAI), address(waWETH));
        assertEq(pathsDaiWeth.length, 1, "Wrong path length waDAI / waWETH");
        assertEq(pathsDaiWeth[0].length, 1, "Wrong path[0] waDAI / waWETH steps length");
        assertEq(pathsDaiWeth[0][0].pool, address(pool), "Wrong path[0] waDAI / waWETH step pool");
        assertEq(address(pathsDaiWeth[0][0].tokenOut), address(waWETH), "Wrong path[0] waDAI / waWETH token out");
        assertFalse(pathsDaiWeth[0][0].isBuffer, "Wrong path[0] waDAI / waWETH step isBuffer");

        // getPathAt returns the correct one
        SwapPathStep[] memory pathDaiWeth0 = registry.getPathAt(address(waDAI), address(waWETH), 0);
        assertEq(
            keccak256(abi.encode(pathDaiWeth0)),
            keccak256(abi.encode(pathsDaiWeth[0])),
            "waDAI / waWETH getPathAt mismatch"
        );
    }

    function testBufferAddPathUninitializedBuffer() external {
        SwapPathStep[] memory steps = new SwapPathStep[](1);

        // USDC is not a buffer.
        steps[0] = SwapPathStep({ pool: address(usdc), tokenOut: usdc, isBuffer: true });

        vm.expectRevert(abi.encodeWithSelector(ITokenPairRegistry.BufferNotInitialized.selector, usdc));
        vm.prank(admin);
        registry.addPath(address(waUSDC), steps);
    }

    function testBufferAddPathWrongUnderlying() external {
        SwapPathStep[] memory steps = new SwapPathStep[](1);

        // Unwrap(waUSDC) != dai
        steps[0] = SwapPathStep({ pool: address(waUSDC), tokenOut: dai, isBuffer: true });

        vm.expectRevert(abi.encodeWithSelector(ITokenPairRegistry.InvalidBufferPath.selector, waUSDC, waUSDC, dai));
        vm.prank(admin);
        registry.addPath(address(waUSDC), steps);
    }

    function testBufferAddPathWrongWrapped() external {
        SwapPathStep[] memory steps = new SwapPathStep[](1);

        // Wrap(USDC) != waDAI
        steps[0] = SwapPathStep({ pool: address(waUSDC), tokenOut: waDAI, isBuffer: true });

        vm.expectRevert(abi.encodeWithSelector(ITokenPairRegistry.InvalidBufferPath.selector, waUSDC, usdc, waDAI));
        vm.prank(admin);
        registry.addPath(address(usdc), steps);
    }

    function testBufferAddPathWrongTokenIn() external {
        SwapPathStep[] memory steps = new SwapPathStep[](1);

        steps[0] = SwapPathStep({ pool: address(waUSDC), tokenOut: usdc, isBuffer: true });

        vm.expectRevert(abi.encodeWithSelector(ITokenPairRegistry.InvalidBufferPath.selector, waUSDC, weth, usdc));
        vm.prank(admin);
        registry.addPath(address(weth), steps);
    }

    function testBufferAddSimplePath() external {
        _expectEmitPathAddedEvents(address(weth), address(waWETH));
        vm.prank(admin);
        registry.addSimplePath(address(waWETH));

        assertEq(registry.getPathCount(address(weth), address(waWETH)), 1, "Wrong path count weth / waWETH");
        assertEq(registry.getPathCount(address(waWETH), address(weth)), 1, "Wrong path count waWETH / weth");

        SwapPathStep[][] memory pathsWrap = registry.getPaths(address(weth), address(waWETH));
        assertEq(pathsWrap.length, 1, "Wrong path length weth / waWETH");
        assertEq(pathsWrap[0].length, 1, "Wrong path[0] weth / waWETH steps length");
        assertEq(pathsWrap[0][0].pool, address(waWETH), "Wrong path[0] weth / waWETH step pool");
        assertEq(address(pathsWrap[0][0].tokenOut), address(waWETH), "Wrong path[0] weth / waWETH token out");
        assertTrue(pathsWrap[0][0].isBuffer, "Wrong path[0] weth / waWETH step isBuffer");

        // getPathAt returns the correct one
        SwapPathStep[] memory pathWrap0 = registry.getPathAt(address(weth), address(waWETH), 0);
        assertEq(
            keccak256(abi.encode(pathWrap0)),
            keccak256(abi.encode(pathsWrap[0])),
            "weth / waWETH getPathAt mismatch"
        );

        SwapPathStep[][] memory pathsUnwrap = registry.getPaths(address(waWETH), address(weth));
        assertEq(pathsUnwrap.length, 1, "Wrong path length waWETH / weth");
        assertEq(pathsUnwrap[0].length, 1, "Wrong path[0] waWETH / weth steps length");
        assertEq(pathsUnwrap[0][0].pool, address(waWETH), "Wrong path[0] waWETH / weth step pool");
        assertEq(address(pathsUnwrap[0][0].tokenOut), address(weth), "Wrong path[0] waWETH / weth token out");
        assertTrue(pathsUnwrap[0][0].isBuffer, "Wrong path[0] waWETH / weth step isBuffer");

        // getPathAt returns the correct one
        SwapPathStep[] memory pathUnwrap0 = registry.getPathAt(address(waWETH), address(weth), 0);
        assertEq(
            keccak256(abi.encode(pathUnwrap0)),
            keccak256(abi.encode(pathsUnwrap[0])),
            "waWETH / weth getPathAt mismatch"
        );
    }

    function testRemovePathAtIndexPermissioned() external {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        registry.removePathAtIndex(address(waDAI), address(waWETH), 0);
    }

    function testRemovePathAtIndexOutOfBounds() external {
        vm.expectRevert(ITokenPairRegistry.IndexOutOfBounds.selector);
        vm.prank(admin);
        registry.removePathAtIndex(address(waDAI), address(waWETH), 0);
    }

    function testRemovePathAtIndex() external {
        vm.startPrank(admin);
        registry.addSimplePath(pool);
        registry.addSimplePath(otherPool);
        vm.stopPrank();

        assertEq(registry.getPathCount(address(waDAI), address(waWETH)), 2, "Wrong path count waDAI / waWETH");
        assertEq(
            registry.getPathAt(address(waDAI), address(waWETH), 0)[0].pool,
            address(pool),
            "Wrong waDAI / waWETH path[0] pool"
        );
        assertEq(
            registry.getPathAt(address(waDAI), address(waWETH), 1)[0].pool,
            address(otherPool),
            "Wrong waDAI / waWETH path[1] pool"
        );

        assertEq(registry.getPathCount(address(waWETH), address(waDAI)), 2, "Wrong path count waWETH / waDAI");
        assertEq(
            registry.getPathAt(address(waWETH), address(waDAI), 0)[0].pool,
            address(pool),
            "Wrong waWETH / waDAI path[0] pool"
        );
        assertEq(
            registry.getPathAt(address(waWETH), address(waDAI), 1)[0].pool,
            address(otherPool),
            "Wrong waWETH / waDAI path[1] pool"
        );

        vm.expectEmit();
        emit ITokenPairRegistry.PathRemoved(address(waWETH), address(waDAI), 1);

        vm.prank(admin);
        registry.removePathAtIndex(address(waWETH), address(waDAI), 0);
        assertEq(
            registry.getPathCount(address(waWETH), address(waDAI)),
            1,
            "Wrong path count waWETH / waDAI after remove"
        );
        assertEq(
            registry.getPathCount(address(waDAI), address(waWETH)),
            2,
            "Wrong path count waDAI / waWETH after remove"
        );

        // First path was removed, and second path was moved to the first position.
        assertEq(
            registry.getPathAt(address(waWETH), address(waDAI), 0)[0].pool,
            address(otherPool),
            "Wrong waWETH / waDAI path[0] pool"
        );
        vm.expectRevert(stdError.indexOOBError);
        registry.getPathAt(address(waWETH), address(waDAI), 1);
    }

    function testRemovePathAtIndexMultiHop() external {
        address tokenIn = address(weth);
        address tokenOut = address(dai);
        SwapPathStep[] memory steps = new SwapPathStep[](3);

        steps[0] = SwapPathStep({ pool: address(waWETH), tokenOut: waWETH, isBuffer: true });
        steps[1] = SwapPathStep({ pool: address(pool), tokenOut: waDAI, isBuffer: false });
        steps[2] = SwapPathStep({ pool: address(waDAI), tokenOut: dai, isBuffer: true });

        vm.prank(admin);
        registry.addPath(tokenIn, steps);

        steps[1] = SwapPathStep({ pool: address(otherPool), tokenOut: waDAI, isBuffer: false });
        vm.prank(admin);
        registry.addPath(tokenIn, steps);

        assertEq(registry.getPathCount(tokenIn, tokenOut), 2, "Wrong path count tokenIn / tokenOut");
        assertEq(registry.getPaths(tokenIn, tokenOut).length, 2, "Wrong path length tokenIn / tokenOut");
        assertEq(registry.getPathAt(tokenIn, tokenOut, 0).length, 3, "Wrong path[0] steps length tokenIn / tokenOut");
        assertEq(registry.getPathAt(tokenIn, tokenOut, 1).length, 3, "Wrong path[1] steps length tokenIn / tokenOut");
        assertEq(registry.getPathAt(tokenIn, tokenOut, 0)[1].pool, pool, "Wrong path[0][1] tokenIn / tokenOut pool");

        vm.expectEmit();
        emit ITokenPairRegistry.PathRemoved(address(tokenIn), address(tokenOut), 1);

        vm.prank(admin);
        registry.removePathAtIndex(address(tokenIn), address(tokenOut), 0);
        assertEq(registry.getPathCount(tokenIn, tokenOut), 1, "Wrong path count tokenIn / tokenOut after remove");
        assertEq(registry.getPaths(tokenIn, tokenOut).length, 1, "Wrong path length tokenIn / tokenOut after remove");
        assertEq(
            registry.getPathAt(tokenIn, tokenOut, 0).length,
            3,
            "Wrong path[0] steps length tokenIn / tokenOut after remove"
        );
        // First path is replaced deleted and replaced by the second one
        assertEq(
            registry.getPathAt(tokenIn, tokenOut, 0)[1].pool,
            otherPool,
            "Wrong path[0][1] tokenIn / tokenOut pool after remove"
        );
    }

    function testRemovePathAtIndexWithDuplicates() external {
        address tokenIn = address(dai);
        address tokenOut = address(waDAI);

        // Redundant wrap / unwrap
        SwapPathStep[] memory steps = new SwapPathStep[](3);
        steps[0] = SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
        steps[1] = SwapPathStep({ pool: address(waDAI), tokenOut: dai, isBuffer: true });
        steps[2] = SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });

        vm.prank(admin);
        registry.addPath(tokenIn, steps);

        vm.prank(admin);
        registry.addPath(tokenIn, steps);

        vm.prank(admin);
        registry.addSimplePath(address(waDAI));

        vm.prank(admin);
        registry.addPath(tokenIn, steps);

        assertEq(registry.getPathCount(tokenIn, tokenOut), 4, "Wrong path count tokenIn / tokenOut");
        assertEq(registry.getPathAt(tokenIn, tokenOut, 2).length, 1, "Wrong simple path position");

        // This will remove the simple path of length 1
        vm.prank(admin);
        registry.removeSimplePath(address(waDAI));

        assertEq(registry.getPathCount(tokenIn, tokenOut), 3, "Wrong path count tokenIn / tokenOut after remove");
        assertEq(registry.getPathAt(tokenIn, tokenOut, 2).length, 3, "Wrong path reorganization after remove");
    }

    function testRemoveSimplePathNonRegisteredPoolOrBuffer() external {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ITokenPairRegistry.InvalidSimplePath.selector, address(123)));
        registry.removeSimplePath(address(123));
    }

    function testRemoveSimplePathPermissioned() external {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        registry.removeSimplePath(pool);
    }

    function testRemoveRegisteredPoolInexistentPath() external {
        (address tokenA, address tokenB) = address(waDAI) < address(waWETH)
            ? (address(waDAI), address(waWETH))
            : (address(waWETH), address(waDAI));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ITokenPairRegistry.InvalidRemovePath.selector, pool, tokenA, tokenB));
        registry.removeSimplePath(pool);
    }

    function testPoolRemoveSimplePath() external {
        registry.getPaths(address(waWETH), address(waDAI));

        vm.startPrank(admin);
        registry.addSimplePath(pool);
        vm.stopPrank();

        assertEq(registry.getPathCount(address(waDAI), address(waWETH)), 1, "Wrong path count waDAI / waWETH");
        assertEq(registry.getPathCount(address(waWETH), address(waDAI)), 1, "Wrong path count waWETH / waDAI");

        _expectEmitPathRemovedEvents(address(waDAI), address(waWETH));
        vm.prank(admin);
        registry.removeSimplePath(pool);
        assertEq(
            registry.getPathCount(address(waWETH), address(waDAI)),
            0,
            "Wrong path count waWETH / waDAI after remove"
        );
        assertEq(
            registry.getPathCount(address(waDAI), address(waWETH)),
            0,
            "Wrong path count waDAI / waWETH after remove"
        );
    }

    function testBufferRemoveSimplePath() external {
        registry.getPaths(address(weth), address(waWETH));

        vm.startPrank(admin);
        registry.addSimplePath(address(waWETH));
        vm.stopPrank();

        assertEq(registry.getPathCount(address(weth), address(waWETH)), 1, "Wrong path count weth / waWETH");
        assertEq(registry.getPathCount(address(waWETH), address(weth)), 1, "Wrong path count waWETH / weth");

        _expectEmitPathRemovedEvents(address(weth), address(waWETH));
        vm.prank(admin);
        registry.removeSimplePath(address(waWETH));
        assertEq(
            registry.getPathCount(address(weth), address(waWETH)),
            0,
            "Wrong path count waWETH / weth after remove"
        );
        assertEq(
            registry.getPathCount(address(waWETH), address(weth)),
            0,
            "Wrong path count waWETH / weth after remove"
        );
    }

    function _expectEmitPathAddedEvents(address tokenA, address tokenB) internal {
        // The order of the tokens determines the order of the events
        (tokenA, tokenB) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));
        vm.expectEmit();
        emit ITokenPairRegistry.PathAdded(address(tokenA), address(tokenB), 1);

        vm.expectEmit();
        emit ITokenPairRegistry.PathAdded(address(tokenB), address(tokenA), 1);
    }

    function _expectEmitPathRemovedEvents(address tokenA, address tokenB) internal {
        // The order of the tokens determines the order of the events
        (tokenA, tokenB) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));
        vm.expectEmit();
        emit ITokenPairRegistry.PathRemoved(address(tokenA), address(tokenB), 0);

        vm.expectEmit();
        emit ITokenPairRegistry.PathRemoved(address(tokenB), address(tokenA), 0);
    }
}
