// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

/**
 * @notice Balancer V3 LBP hook that enforces KYC verification and optional per-address purchase cap on project tokens.
 * @dev This hook is designed to be deployed as a secondary hook through the LBP factory (necessary because we need to
 * know the tokens, which are unknown to the pool at deployment time). KYC is always enabled; the cap is optional.
 */
contract LBPKYCHook is BaseHooks, VaultGuard, EIP712 {
    // EIP-712 type hash for the KYC authorization struct.
    bytes32 public constant KYC_AUTHORIZATION_TYPEHASH =
        keccak256("KYCAuthorization(address user,address pool,uint256 deadline)");

    string public constant EIP712_NAME = "BalancerLBPCapHook";
    string public constant EIP712_VERSION = "1.0";

    /// @notice The router trusted to accurately report the sender via `ISenderGuard.getSender()`.
    address internal immutable _trustedRouter;

    /**
     * @notice The address of the token to be restricted (or the zero address if there is no cap.
     * @dev This hook applies to a single pool instance, so the token and allocation should be set by the pool factory.
     */
    IERC20 internal immutable _cappedToken;

    // Scaling factor of the capped token (used for events).
    uint256 internal immutable _cappedTokenScalingFactor;

    /**
     * @notice Maximum capped tokens a single address may acquire, if the cap is enabled.
     * @dev This hook applies to a single pool instance, so the token and allocation should be set by the pool factory.
     */
    uint256 internal immutable _maxCappedTokenAmountScaled18;

    // Address authorized to sign KYC approvals.
    address internal immutable _authorizedSigner;

    // Cumulative capped tokens bought per user address, as an 18-decimal FixedPoint number.
    mapping(address user => uint256 totalCappedTokenAmount) internal _totalCappedTokenAmountScaled18;

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
     * @notice The recovered signer is not in the authorized signers set.
     * @param signer The unauthorized signer
     */
    error UnauthorizedSigner(address signer);

    /**
     * @notice The swap would push the user's cumulative capped token acquisition over the cap.
     * @param requestedAmountRaw The capped tokens the user is trying to acquire in this swap
     * @param remainingAllocationRaw The remaining allocation available to the user
     */
    error CapExceeded(uint256 requestedAmountRaw, uint256 remainingAllocationRaw);

    /**
     * @notice Deploy a new KYCCapHook.
     * @dev The token and capped amounts will differ per LBP, and only the factory knows these at pool deployment time,
     * so these values must be computed there and passed in.
     *
     * @param vault The Balancer V3 Vault
     * @param trustedRouter The router that reliably reports the end-user sender address
     * @param cappedToken The token on which the cap is imposed (e.g., projectToken)
     * @param maxCappedTokenAmountRaw The maximum number of capped tokens allowed per address
     * @param authorizedSigner Address authorized to sign KYC approvals
     */
    constructor(
        IVault vault,
        address trustedRouter,
        IERC20 cappedToken,
        uint256 maxCappedTokenAmountRaw,
        address authorizedSigner
    ) VaultGuard(vault) EIP712(EIP712_NAME, EIP712_VERSION) {
        _trustedRouter = trustedRouter;
        _cappedToken = cappedToken;
        _authorizedSigner = authorizedSigner;

        // Used for computing raw amounts for output in events.
        _cappedTokenScalingFactor = 10 ** (18 - IERC20Metadata(address(cappedToken)).decimals());
        _maxCappedTokenAmountScaled18 = maxCappedTokenAmountRaw * _cappedTokenScalingFactor;
    }

    /***************************************************************************
                                  Hook Functions
    ***************************************************************************/

    /// @inheritdoc BaseHooks
    function getHookFlags() public view override returns (HookFlags memory hookFlags) {
        // KYC is always enforced before the swap.
        hookFlags.shouldCallBeforeSwap = true;

        // Cap enforcement happens after the swap, when we know the exact amounts.
        if (_maxCappedTokenAmountScaled18 != type(uint256).max) {
            hookFlags.shouldCallAfterSwap = true;
        }
    }

    /// @inheritdoc BaseHooks
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public override returns (bool) {
        _setAuthorizedCaller(factory, pool, address(_vault));

        emit LBPKYCHookRegistered(pool, factory);

        return true;
    }

    /***************************************************************************
                          KYC Enforcement (onBeforeSwap)
    ***************************************************************************/

    /**
     * @notice Validates KYC authorization before a swap is executed.
     * @dev The user must include an EIP-712 signature in `params.userData`, encoded as:
     * `abi.encode(uint256 deadline, bytes signature)`
     * where the signature covers `KYCAuthorization(user, pool, deadline)` and was signed by an authorized signer.
     *
     * The actual user address is obtained from the trusted router's `getSender()`. The router address is
     * provided by the Vault and is trustworthy, but we must verify it is our trusted router to ensure
     * `getSender()` returns the real end-user.
     *
     * @param params The swap parameters, including `userData` with the KYC signature
     * @param pool The pool address (included in the signed payload for cross-pool replay protection)
     * @return success True if KYC validation passes
     */
    function onBeforeSwap(
        PoolSwapParams calldata params,
        address pool
    ) public view override onlyAuthorizedCaller returns (bool success) {
        // The Vault reliably reports which router initiated the swap, but routers are permissionless —
        // we must verify it's one we trust to accurately report the sender.
        require(params.router == _trustedRouter, RouterNotTrusted(params.router));

        // Decode the KYC authorization from userData.
        (uint256 deadline, bytes memory signature) = abi.decode(params.userData, (uint256, bytes));

        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp <= deadline, KYCExpired());

        address endUser = ISenderGuard(params.router).getSender();

        // Build the EIP-712 struct hash and recover the signer.
        bytes32 structHash = keccak256(abi.encode(KYC_AUTHORIZATION_TYPEHASH, endUser, pool, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, signature);

        require(_authorizedSigner == signer, UnauthorizedSigner(signer));

        return true;
    }

    /***************************************************************************
                          Cap Enforcement (onAfterSwap)
    ***************************************************************************/

    /**
     * @notice Enforces the per-address allocation cap after a swap is executed.
     * @dev Only tracks swaps where the user is *buying* capped tokens (i.e., the capped token is `tokenOut`).
     * Selling project tokens back into the pool does NOT decrease the tracked allocation — this is intentional
     * to prevent wash-trading exploits where a user buys, transfers to another wallet, sells back, and buys again.
     *
     * Uses `amountOutScaled18` to track uniformly regardless of swap kind (EXACT_IN / EXACT_OUT).
     *
     * @param params The after-swap parameters containing amounts and token info
     * @return success True if the cap is not exceeded
     * @return amountCalculatedRaw The calculated swap amount
     */
    function onAfterSwap(AfterSwapParams calldata params) public override onlyAuthorizedCaller returns (bool, uint256) {
        // Only enforce cap when user is buying capped tokens.

        if (address(params.tokenOut) == address(_cappedToken)) {
            // Router was already validated in onBeforeSwap, but verify here too for defense-in-depth.
            require(params.router == _trustedRouter, RouterNotTrusted(params.router));

            address endUser = ISenderGuard(params.router).getSender();

            // amountOutScaled18 is the amount of capped tokens leaving the pool, regardless of EXACT_IN/EXACT_OUT.
            uint256 cappedTokensOut = params.amountOutScaled18;
            uint256 previousTotal = _totalCappedTokenAmountScaled18[endUser];
            uint256 newTotal = previousTotal + cappedTokensOut;

            uint256 cappedTokensOutRaw = _toRaw(cappedTokensOut, _cappedTokenScalingFactor);

            if (newTotal > _maxCappedTokenAmountScaled18) {
                // Could be unchecked, but don't need to optimize a revert path.
                uint256 amountRemaining = _maxCappedTokenAmountScaled18 - previousTotal;

                revert CapExceeded(cappedTokensOutRaw, _toRaw(amountRemaining, _cappedTokenScalingFactor));
            }

            _totalCappedTokenAmountScaled18[endUser] = newTotal;

            emit CappedTokensBought(endUser, _cappedToken, cappedTokensOutRaw);
        }

        return (true, params.amountCalculatedRaw);
    }

    /***************************************************************************
                                Helper Functions
    ***************************************************************************/

    /// @notice Returns the remaining allocation (scaled18) for a given user. Returns max if cap is disabled.
    function remainingAllocation(address user) external view returns (uint256) {
        return _maxCappedTokenAmountScaled18 - _totalCappedTokenAmountScaled18[user];
    }

    /// @notice Returns the EIP-712 domain separator for off-chain signing tools.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _toRaw(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return amount / scalingFactor;
    }
}
