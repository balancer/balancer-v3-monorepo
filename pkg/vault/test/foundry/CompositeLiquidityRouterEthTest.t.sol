// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { CompositeLiquidityRouterERC4626PoolTest } from "./CompositeLiquidityRouterERC4626Pool.t.sol";

/**
 * @notice Test CompositeLiquidityRouter ETH permanently locked on proportional ERC4626 pool remove liquidity.
 * @dev Root cause: `removeLiquidityERC4626PoolProportionalHook` is the only ERC4626 pool hook that does NOT call
 * `_returnEth(params.sender)`. Both add-liquidity hooks end with that call. The entry point is `external payable`
 * with the plain `saveSender` modifier, which does not sweep ETH (only `saveSenderAndManageEth` does).
 *
 * Any ETH in msg.value is permanently locked; `receive()` rejects non-WETH senders, so there is no recovery.
 */
contract CompositeLiquidityRouterEthTest is CompositeLiquidityRouterERC4626PoolTest {
    uint256 internal constant EXCESS_ETH = 1 ether;

    function testRemoveLiquidityERC4626PoolProportionalExcessEth() public {
        vm.deal(bob, bob.balance + EXCESS_ETH);

        uint256 bobEthBefore = bob.balance;
        uint256 exactBptAmountIn = IERC20(pool).balanceOf(bob) / 4;

        uint256[] memory minAmountsOut = new uint256[](2);
        bool[] memory unwrapWrapped = _getAllTrue(minAmountsOut.length);

        vm.prank(bob);
        compositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool{ value: EXCESS_ETH }(
            pool,
            unwrapWrapped,
            exactBptAmountIn,
            minAmountsOut,
            false, // wethIsEth — keep tokens as ERC20, only ETH in play is msg.value
            bytes("")
        );

        assertEq(address(compositeLiquidityRouter).balance, 0, "router should not hold ETH");
        assertEq(bob.balance, bobEthBefore, "bob should recover excess ETH");
    }
}
