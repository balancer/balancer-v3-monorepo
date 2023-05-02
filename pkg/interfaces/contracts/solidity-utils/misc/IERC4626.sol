// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import "../openzeppelin/IERC20.sol";

interface IERC4626 is IERC20 {
    /**
     * @dev `caller` has exchanged `assets` for `shares`, and transferred those `shares` to `owner`.
     */
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    /**
     * @dev `caller` has exchanged `shares`, owned by `owner`, for `assets`,
     *      and transferred those `assets` to `receiver`.
     */
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /**
     * @dev Mints `shares` Vault shares to `receiver` by depositing exactly `amount` of underlying tokens.
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /**
     * @dev Burns exactly `shares` from `owner` and sends `assets` of underlying tokens to `receiver`.
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /**
     * @dev The address of the underlying token that the Vault uses for accounting, depositing, and withdrawing.
     */
    function asset() external view returns (address);

    /**
     * @dev Total amount of the underlying asset that is “managed” by Vault.
     */
    function totalAssets() external view returns (uint256);

    /**
     * @dev The amount of `assets` that the Vault would exchange for the amount
     *      of `shares` provided, in an ideal scenario where all the conditions are met.
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /**
     * @dev The amount of `shares` that the Vault would exchange for the amount
     *      of `assets` provided, in an ideal scenario where all the conditions are met.
     */
    function convertToShares(uint256 assets) external view returns (uint256 shares);
}
