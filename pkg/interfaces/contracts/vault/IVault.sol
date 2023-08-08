// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { Asset } from "../solidity-utils/misc/Asset.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVault {
    /*******************************************************************************
                                    Pool Registration
    *******************************************************************************/

    function registerPool(address factory, IERC20[] memory tokens) external;

    function isRegisteredPool(address pool) external view returns (bool);

    function getPoolTokens(address pool) external view returns (IERC20[] memory tokens, uint256[] memory balances);

    /*******************************************************************************
                                 ERC20 Balancer Pool Tokens 
    *******************************************************************************/

    function totalSupplyOfERC20(address token) external view returns (uint256);

    function balanceOfERC20(address token, address account) external view returns (uint256);

    function transferERC20(address owner, address to, uint256 amount) external returns (bool);

    function transferFromERC20(address spender, address from, address to, uint256 amount) external returns (bool);

    function allowanceOfERC20(address token, address owner, address spender) external view returns (uint256);

    function approveERC20(address sender, address spender, uint256 amount) external returns (bool);

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    function invoke(bytes calldata data) external payable returns (bytes memory result);

    function settle(IERC20 token) external returns (uint256 paid);

    function wire(IERC20 token, address to, uint256 amount) external;

    function mint(IERC20 token, address to, uint256 amount) external;

    function retrieve(IERC20 token, address from, uint256 amount) external;

    function burn(IERC20 token, address owner, uint256 amount) external;

    function getHandler() external view returns (address);

    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    function swap(
        SwapParams memory params
    ) external returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut);

    struct SwapParams {
        SwapKind kind;
        /// @notice Address of the pool
        address pool;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountGiven;
        uint256 limit;
        uint256 deadline;
        bytes userData;
    }

    event Swap(
        address indexed pool,
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    function addLiquidity(
        address pool,
        IERC20[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    function removeLiquidity(
        address pool,
        IERC20[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);

    event PoolBalanceChanged(address indexed pool, address indexed liquidityProvider, IERC20[] tokens, int256[] deltas);
}
