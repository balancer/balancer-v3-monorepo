// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { ERC4626TestToken } from "../../../contracts/test/ERC4626TestToken.sol";
import { ERC20TestToken } from "../../../contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "../../../contracts/test/WETHTestToken.sol";

struct Accounts {
    // Default admin.
    address payable admin;
    uint256 adminKey;
    // Default liquidity provider.
    address payable lp;
    uint256 lpKey;
    // Default user.
    address payable alice;
    uint256 aliceKey;
    // Default counterparty.
    address payable bob;
    uint256 bobKey;
    // Malicious user.
    address payable hacker;
    uint256 hackerKey;
    // Broke user.
    address payable broke;
    uint256 brokeUserKey;
    // List of all users
    address payable[] users;
    uint256[] userKeys;
}

struct TokensInfo {
    // ERC20 tokens used for tests.
    ERC20TestToken dai;
    ERC20TestToken usdc;
    WETHTestToken weth;
    ERC20TestToken wsteth;
    ERC20TestToken veBAL;
    ERC4626TestToken waDAI;
    ERC4626TestToken waWETH;
    ERC4626TestToken waUSDC;
    // List of all ERC20 tokens
    IERC20[] tokens;
    // List of all ERC4626 tokens
    IERC4626[] erc4626Tokens;
}

struct BaseTestState {
    Accounts accounts;
    TokensInfo tokensInfo;
}

abstract contract BaseTest is Test, GasSnapshot {
    using CastingHelpers for *;

    // Reasonable block.timestamp `MAY_1_2023`
    uint32 internal constant START_TIMESTAMP = 1_682_899_200;

    uint256 internal constant DEFAULT_BALANCE = 1e9 * 1e18;

    uint256 internal constant MAX_UINT256 = type(uint256).max;
    // Raw token balances are stored in half a slot, so the max is uint128.
    uint256 internal constant MAX_UINT128 = type(uint128).max;

    // Default balance for accounts
    bool private _initialized;
    uint256 private _defaultBalance = DEFAULT_BALANCE;
    BaseTestState private _state;

    // -------------------- Initializers --------------------
    function setDefaultBalance(uint256 defaultBalance) internal {
        if (_initialized) {
            revert("Default balance can only be set before the test is initialized");
        }

        _defaultBalance = defaultBalance;
    }

    function setUp() public virtual {
        // Set timestamp only if testing locally
        if (block.chainid == 31337) {
            // Set block.timestamp to something better than 0
            vm.warp(START_TIMESTAMP);
        }

        // Deploy the base test contracts.
        ERC20TestToken dai = createERC20("DAI", 18);
        // "USDC" is deliberately 18 decimals to test one thing at a time.
        ERC20TestToken usdc = createERC20("USDC", 18);
        ERC20TestToken wsteth = createERC20("WSTETH", 18);
        ERC20TestToken weth = new WETHTestToken();
        vm.label(address(weth), "WETH");
        ERC20TestToken veBAL = createERC20("veBAL", 18);

        _state.tokensInfo.dai = dai;
        _state.tokensInfo.usdc = usdc;
        _state.tokensInfo.weth = weth;
        _state.tokensInfo.wsteth = wsteth;
        _state.tokensInfo.veBAL = veBAL;

        _state.tokensInfo.tokens.push(dai);
        _state.tokensInfo.tokens.push(usdc);
        _state.tokensInfo.tokens.push(weth);
        _state.tokensInfo.tokens.push(wsteth);
        _state.tokensInfo.tokens.push(veBAL);

        // Deploy ERC4626 tokens.
        ERC4626TestToken waDAI = createERC4626("Wrapped aDAI", "waDAI", 18, dai);
        ERC4626TestToken waWETH = createERC4626("Wrapped aWETH", "waWETH", 18, weth);
        // "waUSDC" is deliberately 18 decimals to test one thing at a time.
        ERC4626TestToken waUSDC = createERC4626("Wrapped aUSDC", "waUSDC", 18, usdc);

        _state.tokensInfo.waDAI = waDAI;
        _state.tokensInfo.waWETH = waWETH;
        _state.tokensInfo.waUSDC = waUSDC;

        // Fill the ERC4626 token list.
        _state.tokensInfo.erc4626Tokens.push(waDAI);
        _state.tokensInfo.erc4626Tokens.push(waWETH);
        _state.tokensInfo.erc4626Tokens.push(waUSDC);

        // Create users for testing.
        (address admin, uint256 adminKey) = createUser("admin");
        (address lp, uint256 lpKey) = createUser("lp");
        (address alice, uint256 aliceKey) = createUser("alice");
        (address bob, uint256 bobKey) = createUser("bob");
        (address hacker, uint256 hackerKey) = createUser("hacker");
        address brokeNonPay;
        uint256 brokeUserKey;
        (brokeNonPay, brokeUserKey) = makeAddrAndKey("broke");
        vm.label(brokeNonPay, "broke");

        _state.accounts.admin = admin;
        _state.accounts.adminKey = adminKey;
        _state.accounts.lp = lp;
        _state.accounts.lpKey = lpKey;
        _state.accounts.alice = alice;
        _state.accounts.aliceKey = aliceKey;
        _state.accounts.bob = bob;
        _state.accounts.bobKey = bobKey;
        _state.accounts.hacker = hacker;
        _state.accounts.hackerKey = hackerKey;
        _state.accounts.broke = payable(brokeNonPay);
        _state.accounts.brokeUserKey = brokeUserKey;

        _state.accounts.users.push(admin);
        _state.accounts.userKeys.push(adminKey);
        _state.accounts.users.push(lp);
        _state.accounts.userKeys.push(lpKey);
        _state.accounts.users.push(alice);
        _state.accounts.userKeys.push(aliceKey);
        _state.accounts.users.push(bob);
        _state.accounts.userKeys.push(bobKey);
        _state.accounts.users.push(hacker);
        _state.accounts.userKeys.push(hackerKey);
        _state.accounts.users.push(payable(brokeNonPay));
        _state.accounts.userKeys.push(brokeUserKey);

        // Must mock rates after giving wrapped tokens to users, but before creating pools and initializing buffers.
        mockERC4626TokenRates();

        _initialized = true;
    }

    function isBaseTestInitialized() internal view returns (bool) {
        return _initialized;
    }

    function getBaseTestState() internal view returns (BaseTestState memory) {
        return _state;
    }

    function getTokens() internal view returns (TokensInfo memory) {
        return _state.tokensInfo;
    }

    function getAccounts() internal view returns (Accounts memory) {
        return _state.accounts;
    }

    // -------------------- Helpers --------------------

    /**
     * @notice Manipulate rates of ERC4626 tokens.
     * @dev It's important to not have a 1:1 rate when testing ERC4626 tokens, so we can differentiate between
     * wrapped and underlying amounts. For certain tests, we may need to override these rates for simplicity.
     */
    function mockERC4626TokenRates() internal virtual {
        _state.tokensInfo.waDAI.inflateUnderlyingOrWrapped(0, 6 * _defaultBalance);
        _state.tokensInfo.waUSDC.inflateUnderlyingOrWrapped(23 * _defaultBalance, 0);
    }

    function getSortedIndexes(
        address tokenA,
        address tokenB
    ) internal pure returns (uint256 idxTokenA, uint256 idxTokenB) {
        idxTokenA = tokenA > tokenB ? 1 : 0;
        idxTokenB = idxTokenA == 0 ? 1 : 0;
    }

    function getSortedIndexes(address[] memory addresses) public pure returns (uint256[] memory sortedIndexes) {
        uint256 length = addresses.length;
        address[] memory sortedAddresses = new address[](length);

        // Clone address array to sortedAddresses, so the original array does not change.
        for (uint256 i = 0; i < length; i++) {
            sortedAddresses[i] = addresses[i];
        }

        sortedAddresses = InputHelpers.sortTokens(sortedAddresses.asIERC20()).asAddress();

        sortedIndexes = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = 0; j < length; j++) {
                if (addresses[i] == sortedAddresses[j]) {
                    sortedIndexes[i] = j;
                }
            }
        }
    }

    /// @dev Creates an ERC20 test token, labels its address.
    function createERC20(string memory name, uint8 decimals) internal returns (ERC20TestToken token) {
        token = new ERC20TestToken(name, name, decimals);
        vm.label(address(token), name);
    }

    /// @dev Creates an ERC4626 test token and labels its address.
    function createERC4626(
        string memory name,
        string memory symbol,
        uint8 decimals,
        IERC20 underlying
    ) internal returns (ERC4626TestToken token) {
        token = new ERC4626TestToken(underlying, name, symbol, decimals);
        vm.label(address(token), symbol);
    }

    /// @dev Generates a user, labels its address, and funds it with test assets.
    function createUser(string memory name) internal returns (address payable, uint256) {
        return createUser(name, _defaultBalance);
    }

    /// @dev Generates a user, labels its address, and funds it with test assets.
    function createUser(string memory name, uint256 balance) internal returns (address payable, uint256) {
        (address user, uint256 key) = makeAddrAndKey(name);
        vm.label(user, name);
        vm.deal(payable(user), balance);

        for (uint256 i = 0; i < _state.tokensInfo.tokens.length; ++i) {
            deal(address(_state.tokensInfotokens[i]), user, balance);
        }

        ERC4626TestToken[] memory erc4626Tokens = _state.tokensInfo.erc4626Tokens;
        for (uint256 i = 0; i < erc4626Tokens.length; ++i) {
            // Give underlying tokens to the user, for depositing in the wrapped token.
            if (erc4626Tokens[i].asset() == address(_state.tokensInfo.weth)) {
                vm.deal(user, user.balance + balance);

                vm.prank(user);
                _state.tokensInfo.weth.deposit{ value: balance }();
            } else {
                ERC20TestToken(erc4626Tokens[i].asset()).mint(user, balance);
            }

            // Deposit underlying to mint wrapped tokens to the user.
            vm.startPrank(user);
            IERC20(erc4626Tokens[i].asset()).approve(address(erc4626Tokens[i]), balance);
            erc4626Tokens[i].deposit(balance, user);
            vm.stopPrank();
        }

        return (payable(user), key);
    }

    function getDecimalScalingFactor(uint8 decimals) internal pure returns (uint256 scalingFactor) {
        require(decimals <= 18, "Decimals must be between 0 and 18");
        uint256 decimalDiff = 18 - decimals;
        scalingFactor = 10 ** decimalDiff;

        return scalingFactor;
    }

    /// @dev Returns `amount - amount/base`; e.g., if base = 100, decrease `amount` by 1%; if 1000, 0.1%, etc.
    function less(uint256 amount, uint256 base) internal pure returns (uint256) {
        return (amount * (base - 1)) / base;
    }
}
