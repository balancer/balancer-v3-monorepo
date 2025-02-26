// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {
    IGyroECLPPool
} from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import "../../contracts/GyroECLPPool.sol";

// Run with: forge test --match-path test/foundry/GyroECLPDebug.t.sol -vv
contract GyroECLPDebug is Test {
    // GyroECLP test pool
    address public constant pool = 0x80fd5bc9d4fA6C22132f8bb2d9d30B01c3336FB3;
    IERC20 tokenIn = IERC20(0xB77EB1A70A96fDAAeB31DB1b42F2b8b5846b2613);
    IERC20 tokenOut = IERC20(0xb19382073c7A0aDdbb56Ac6AF1808Fa49e377B75);
    
    IRouter public constant router = IRouter(0x0BF61f706105EA44694f2e92986bD01C39930280);
    IVault public constant vault = IVault(0xbA1333333333a1BA1108E8412f11850A5C319bA9);


    function setUp() public {
        vm.createSelectFork("YOUR_RPC_URL", 7748718);
        IGyroECLPPool.GyroECLPPoolParams memory params;
        // The EclpParams & DerivedEclpParams values don't matter and won't change the result of the deployed pool but they do need to be reasonable to pass validation checks
        IGyroECLPPool.EclpParams memory eclpParams;
        eclpParams.alpha = 998502246630054917;
        eclpParams.beta = 1000200040008001600;
        eclpParams.c = 707106781186547524;
        eclpParams.s = 707106781186547524;
        eclpParams.lambda = 4000000000000000000000;
        IGyroECLPPool.DerivedEclpParams memory derivedEclpParams;
        derivedEclpParams.tauAlpha.x = -94861212813096057289512505574275160547;
        derivedEclpParams.tauAlpha.y = 31644119574235279926451292677567331630;
        derivedEclpParams.tauBeta.x = 37142269533113549537591131345643981951;
        derivedEclpParams.tauBeta.y = 92846388265400743995957747409218517601;
        derivedEclpParams.u = 66001741173104803338721745994955553010;
        derivedEclpParams.v = 62245253919818011890633399060291020887;
        derivedEclpParams.w = 30601134345582732000058913853921008022;
        derivedEclpParams.z = -28859471639991253843240999485797747790;
        derivedEclpParams.dSq = 99999999999999999886624093342106115200;
        params.eclpParams = eclpParams;
        params.derivedEclpParams = derivedEclpParams;
        GyroECLPPool gyroPool = new GyroECLPPool(params, vault);
        vm.etch(pool, address(gyroPool).code);
    }

    function testFork() public {
         _prankStaticCall();
        uint256 queryAmountOut = router.querySwapSingleTokenExactIn(
            pool,
            tokenIn,
            tokenOut,
            1000000000000000000,
            address(this),
            bytes("")
        );

        // Known result
        assertEq(queryAmountOut, 989980003877180195, "Wrong swap amount out");
    }

    function _prankStaticCall() internal {
        // Prank address 0x0 for both msg.sender and tx.origin (to identify as a staticcall).
        vm.prank(address(0), address(0));
    }
}