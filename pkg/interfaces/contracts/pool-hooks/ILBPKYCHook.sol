// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILBPKYCHook {
    /***************************************************************************
                                    Events
    ***************************************************************************/

    /**
     * @notice Emitted on successful registration with a pool.
     * @param pool The address of the pool to which this hook is attached
     * @param factory The factory from which the pool was deployed
     */
    event LBPKYCHookRegistered(address indexed pool, address indexed factory);

    /**
     * @notice Emitted when a user acquires capped tokens.
     * @param user The user who purchased the capped tokens
     * @param token The capped token address
     * @param amountRaw The amount purchased, in native token decimals
     */
    event CappedTokensBought(address indexed user, IERC20 indexed token, uint256 amountRaw);

    /***************************************************************************
                                    Errors
    ***************************************************************************/

    /**
     * @notice The swap was not routed through the trusted router.
     * @dev Routers are permissionless; we must use one we trust to report the ultimate sender reliably.
     * @param router The address of the untrusted router
     */
    error RouterNotTrusted(address router);

    /// @notice The KYC authorization signature has expired.
    error KYCExpired();

    /**
     * @notice The recovered signer is not the authorized signer.
     * @param signer The unauthorized signer
     */
    error UnauthorizedSigner(address signer);

    /**
     * @notice The swap would push the user's cumulative capped token acquisition over the cap.
     * @param requestedAmountRaw The capped tokens the user is trying to acquire in this swap
     * @param remainingAllocationRaw The remaining allocation available to the user
     */
    error CapExceeded(uint256 requestedAmountRaw, uint256 remainingAllocationRaw);

    /// @notice There is no capped token set for this hook, so the allocation functions cannot be called.
    error NoCappedTokenSet();

    /// @notice The hook was misconfigured (e.g., a cap amount was set with the zero token).
    error InvalidConfiguration();

    /**
     * @notice Returns the trusted router, which is used to initialize and seed the pool.
     * @return trustedRouter Address of the trusted router (i.e., one that reliably reports the sender)
     */
    function getTrustedRouter() external view returns (address trustedRouter);

    /**
     * @notice Returns the authorized signer, which is used to validate KYC approvals for purchases of capped tokens.
     * @dev Factories for pools supporting KYC should be deployed with the singleton KYCAdmin address, and read the
     * current signer at pool creation time to pass to the hook constructor. If the KYC vendor rotates keys, they can
     * update the signer in the KYCAdmin contract; existing pools keep their original signer for the duration of the
     * sale.
     *
     * @return authorizedSigner Address of the authorized signer (i.e., authorized to sign KYC authorizations)
     */
    function getAuthorizedSigner() external view returns (address authorizedSigner);

    /**
     * @notice Returns the capped token for this hook, or the zero address if there is no cap.
     * @dev If a token is capped, the hook will restrict purchases of that token to a maximum cumulative amount per
     * user. The cap is expressed in the token's native decimals, and enforced by reverting if a swap would push a
     * user's cumulative purchases over the cap. The hook tracks cumulative purchases per user, and provides a getter
     * for the remaining allocation.
     *
     * @return cappedToken The address of the capped token, or the zero address if there is no cap
     */
    function getCappedToken() external view returns (IERC20 cappedToken);

    /**
     * @notice Returns the total amount of capped tokens a user has purchased so far.
     * @param user The user address
     * @return totalCappedTokenAmountRaw The total amount of capped tokens the user purchased, in native token decimals
     */
    function getCappedTokenAllocationUsed(address user) external view returns (uint256 totalCappedTokenAmountRaw);

    /**
     * @notice Returns the remaining allocation for a user. Returns max if cap is disabled.
     * @param user The address of the user
     * @return remainingAllocationRaw The remaining allocation for the user, in native token decimals
     */
    function getCappedTokenAllocationRemaining(address user) external view returns (uint256 remainingAllocationRaw);

    /**
     * @notice EIP-712 domain separator is cached in the EIP712 base contract, but not exposed.
     * @dev This function allows off-chain tools to retrieve it for signing without duplicating logic.
     * @return domainSeparatorV4 The EIP-712 domain separator used in the KYC authorization signatures.
     */
    function domainSeparator() external view returns (bytes32 domainSeparatorV4);
}
