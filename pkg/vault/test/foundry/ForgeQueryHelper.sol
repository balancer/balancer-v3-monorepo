// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";

library ForgeQueryHelper {

    /**
     * @dev Forge can send transactions from `address(0)`, but doing so mints pool tokens even without pulling tokens
     * from the user.
     * This helper wraps the call between a snapshot to revert the state change, which would be equivalent to a static
     * call.
     */
    function staticQueryAddLiquidity(
        Vm vm,
        IRouter router,
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        IVault.AddLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        uint256 snapshot = vm.snapshot();
        vm.prank(address(0), address(0));
        (amountsIn, bptAmountOut, returnData) = router.queryAddLiquidity(
            pool,
            maxAmountsIn,
            minBptAmountOut,
            kind,
            userData
        );
        vm.revertTo(snapshot);
    }
}
