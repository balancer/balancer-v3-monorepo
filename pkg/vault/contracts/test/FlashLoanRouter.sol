// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

contract FlashLoanRouter {
    using Address for address payable;

    IVault private immutable _vault;

    constructor(IVault vault) {
        _vault = vault;
    }

    function flashloan(IERC20 token, uint256 amount) external payable {
        _vault.invoke(abi.encodeWithSelector(FlashLoanRouter.flashloanCallback.selector, token, amount));
    }

    function flashloanCallback(IERC20 token, uint256 amount) external {
        _vault.wire(token, address(this), amount);
        token.approve(address(_vault), type(uint256).max);
        _vault.retrieve(token, address(this), amount);
    }
}
