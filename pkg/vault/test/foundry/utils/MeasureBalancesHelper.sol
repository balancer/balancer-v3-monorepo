// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";

import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";

contract MeasureBalancesHelper {
    IERC20 private _dai;
    IERC20 private _usdc;
    address private _pool;
    address private _hook;
    address private _bob;
    address private _lp;

    IVaultMock private _vault;

    function prepareMeasurement(
        IERC20 dai,
        IERC20 usdc,
        address pool,
        address hook,
        address bob,
        address lp,
        IVaultMock vault
    ) public {
        _dai = dai;
        _usdc = usdc;
        _pool = pool;
        _hook = hook;
        _bob = bob;
        _lp = lp;
        _vault = vault;
    }

    struct WalletState {
        uint256 daiBefore;
        uint256 daiAfter;
        uint256 usdcBefore;
        uint256 usdcAfter;
        uint256 bptBefore;
        uint256 bptAfter;
    }

    struct HookTestLocals {
        WalletState bob;
        WalletState lp;
        WalletState hook;
        WalletState vault;
        uint256[] poolBefore;
        uint256[] poolAfter;
        uint256 bptSupplyBefore;
        uint256 bptSupplyAfter;
    }

    function _measureBalancesBeforeOperation() internal view returns (HookTestLocals memory vars) {
        vars.bob.daiBefore = _dai.balanceOf(_bob);
        vars.bob.usdcBefore = _usdc.balanceOf(_bob);
        vars.bob.bptBefore = BalancerPoolToken(_pool).balanceOf(_bob);
        vars.lp.daiBefore = _dai.balanceOf(_lp);
        vars.lp.usdcBefore = _usdc.balanceOf(_lp);
        vars.lp.bptBefore = BalancerPoolToken(_pool).balanceOf(_lp);
        vars.hook.daiBefore = _dai.balanceOf(_hook);
        vars.hook.usdcBefore = _usdc.balanceOf(_hook);
        vars.vault.daiBefore = _dai.balanceOf(address(_vault));
        vars.vault.usdcBefore = _usdc.balanceOf(address(_vault));
        vars.poolBefore = _vault.getRawBalances(_pool);
        vars.bptSupplyBefore = BalancerPoolToken(_pool).totalSupply();
    }

    function _measureBalancesAfterOperation(HookTestLocals memory vars) internal view {
        vars.bob.daiAfter = _dai.balanceOf(_bob);
        vars.bob.usdcAfter = _usdc.balanceOf(_bob);
        vars.bob.bptAfter = BalancerPoolToken(_pool).balanceOf(_bob);
        vars.lp.daiAfter = _dai.balanceOf(_lp);
        vars.lp.usdcAfter = _usdc.balanceOf(_lp);
        vars.lp.bptAfter = BalancerPoolToken(_pool).balanceOf(_lp);
        vars.hook.daiAfter = _dai.balanceOf(_hook);
        vars.hook.usdcAfter = _usdc.balanceOf(_hook);
        vars.vault.daiAfter = _dai.balanceOf(address(_vault));
        vars.vault.usdcAfter = _usdc.balanceOf(address(_vault));
        vars.poolAfter = _vault.getRawBalances(_pool);
        vars.bptSupplyAfter = BalancerPoolToken(_pool).totalSupply();
    }
}
