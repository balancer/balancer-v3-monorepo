// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { DeployPermit2 } from "permit2/test/utils/DeployPermit2.sol";

import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IStdMedusaCheats } from "@balancer-labs/v3-interfaces/contracts/test/IStdMedusaCheats.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { VaultExtensionMock } from "../../../contracts/test/VaultExtensionMock.sol";
import { VaultAdminMock } from "../../../contracts/test/VaultAdminMock.sol";
import { VaultMock } from "../../../contracts/test/VaultMock.sol";
import { ProtocolFeeController } from "../../../contracts/ProtocolFeeController.sol";
import { BasicAuthorizerMock } from "../../../contracts/test/BasicAuthorizerMock.sol";
import { RouterMock } from "../../../contracts/test/RouterMock.sol";
import { BatchRouterMock } from "../../../contracts/test/BatchRouterMock.sol";
import { CompositeLiquidityRouterMock } from "../../../contracts/test/CompositeLiquidityRouterMock.sol";
import { ProtocolFeeControllerMock } from "../../../contracts/test/ProtocolFeeControllerMock.sol";
import { PoolFactoryMock } from "../../../contracts/test/PoolFactoryMock.sol";

contract BaseMedusaTest is Test {
    // Forge has vm commands, which allow us to prank callers, deal ETH and ERC20 tokens to users, etc. Medusa is not
    // compatible with it and has its own StdCheats, in the address below. So, instead of calling `vm.prank`, we should
    // use `medusa.prank`. The interface documents which functions are available. Notice that Medusa's StdCheats and
    // Forge's StdCheats implement different methods.
    IStdMedusaCheats internal medusa = IStdMedusaCheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    // In certain places, console.log will not print to stdout the intended message, so we use this event to print
    // messages and values.
    event Debug(string, uint256);

    IPermit2 internal permit2;

    // Main contract mocks.
    IVaultMock internal vault;
    IVaultExtension internal vaultExtension;
    IVaultAdmin internal vaultAdmin;
    RouterMock internal router;
    BatchRouterMock internal batchRouter;
    CompositeLiquidityRouterMock internal compositeLiquidityRouter;
    BasicAuthorizerMock internal authorizer;
    ProtocolFeeControllerMock internal feeController;
    PoolFactoryMock internal factoryMock;

    IBasePool internal pool;
    uint256 internal poolCreationNonce;

    uint256 internal constant DEFAULT_USER_BALANCE = 1e18 * 1e18;
    uint256 internal constant DEFAULT_INITIAL_POOL_BALANCE = 1e6 * 1e18;

    // Set alice,bob and lp to addresses of medusa.json "senderAddresses" property
    address internal alice = address(0x10000);
    address internal bob = address(0x20000);
    address internal lp = address(0x30000);

    ERC20TestToken internal dai;
    ERC20TestToken internal usdc;
    ERC20TestToken internal weth;

    constructor() {
        dai = _createERC20TestToken("DAI", "DAI", 18);
        usdc = _createERC20TestToken("USDC", "USDC", 18);
        weth = _createERC20TestToken("WETH", "WETH", 18);

        DeployPermit2 _deployPermit2 = new DeployPermit2();
        permit2 = IPermit2(_deployPermit2.deployPermit2());

        _deployVaultMock(0, 0);

        router = new RouterMock(IVault(address(vault)), IWETH(address(weth)), permit2);
        batchRouter = new BatchRouterMock(IVault(address(vault)), IWETH(address(weth)), permit2);
        compositeLiquidityRouter = new CompositeLiquidityRouterMock(
            IVault(address(vault)),
            IWETH(address(weth)),
            permit2
        );

        _setPermissionsForUsersAndTokens();

        (IERC20[] memory tokens, uint256[] memory initialBalances) = getTokensAndInitialBalances();
        pool = IBasePool(createPool(tokens, initialBalances));

        _allowBptTransfers();
    }

    function createPool(IERC20[] memory tokens, uint256[] memory initialBalances) internal virtual returns (address) {
        address newPool = factoryMock.createPool("ERC20 Pool", "ERC20POOL");

        // No hooks contract.
        factoryMock.registerTestPool(newPool, vault.buildTokenConfig(tokens), address(0), lp);

        // Initialize liquidity of new pool.
        medusa.prank(lp);
        router.initialize(address(newPool), tokens, initialBalances, 0, false, bytes(""));

        return newPool;
    }

    function getTokensAndInitialBalances()
        internal
        virtual
        returns (IERC20[] memory tokens, uint256[] memory initialBalances)
    {
        tokens = new IERC20[](3);
        tokens[0] = dai;
        tokens[1] = usdc;
        tokens[2] = weth;
        tokens = InputHelpers.sortTokens(tokens);

        initialBalances = new uint256[](3);
        initialBalances[0] = DEFAULT_INITIAL_POOL_BALANCE;
        initialBalances[1] = DEFAULT_INITIAL_POOL_BALANCE;
        initialBalances[2] = DEFAULT_INITIAL_POOL_BALANCE;
    }

    function _createERC20TestToken(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) private returns (ERC20TestToken token) {
        token = new ERC20TestToken(name, symbol, decimals);
        _mintTokenToUsers(token);
    }

    function _mintTokenToUsers(ERC20TestToken token) private {
        token.mint(alice, DEFAULT_USER_BALANCE);
        token.mint(bob, DEFAULT_USER_BALANCE);
        token.mint(lp, DEFAULT_USER_BALANCE);
    }

    function _deployVaultMock(uint256 minTradeAmount, uint256 minWrapAmount) private {
        authorizer = new BasicAuthorizerMock();
        bytes32 salt = bytes32(0);
        VaultMock newVault = VaultMock(payable(CREATE3.getDeployed(salt)));

        bytes memory vaultMockBytecode = type(VaultMock).creationCode;
        vaultAdmin = new VaultAdminMock(
            IVault(payable(address(newVault))),
            90 days,
            30 days,
            minTradeAmount,
            minWrapAmount
        );
        vaultExtension = new VaultExtensionMock(IVault(payable(address(newVault))), vaultAdmin);
        feeController = new ProtocolFeeControllerMock(IVaultMock(payable(address(newVault))));

        _create3(abi.encode(vaultExtension, authorizer, feeController), vaultMockBytecode, salt);

        address poolFactoryMock = newVault.getPoolFactoryMock();
        factoryMock = PoolFactoryMock(poolFactoryMock);

        vault = IVaultMock(address(newVault));
    }

    function _allowBptTransfers() private {
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = lp;

        for (uint256 j = 0; j < users.length; j++) {
            _approveBptTokenForUser(IERC20(address(pool)), users[j]);
        }
    }

    function _approveBptTokenForUser(IERC20 bptToken, address user) private {
        medusa.prank(user);
        bptToken.approve(address(router), type(uint256).max);
        medusa.prank(user);
        bptToken.approve(address(batchRouter), type(uint256).max);
        medusa.prank(user);
        bptToken.approve(address(compositeLiquidityRouter), type(uint256).max);

        medusa.prank(user);
        bptToken.approve(address(permit2), type(uint256).max);
        medusa.prank(user);
        permit2.approve(address(bptToken), address(router), type(uint160).max, type(uint48).max);
        medusa.prank(user);
        permit2.approve(address(bptToken), address(batchRouter), type(uint160).max, type(uint48).max);
        medusa.prank(user);
        permit2.approve(address(bptToken), address(compositeLiquidityRouter), type(uint160).max, type(uint48).max);
    }

    function _setPermissionsForUsersAndTokens() private {
        address[] memory tokens = new address[](3);
        tokens[0] = address(dai);
        tokens[1] = address(usdc);
        tokens[2] = address(weth);

        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = lp;

        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = 0; j < users.length; j++) {
                _approveTokenForUser(tokens[i], users[j]);
            }
        }
    }

    function _approveTokenForUser(address token, address user) private {
        medusa.prank(user);
        IERC20(token).approve(address(permit2), type(uint256).max);
        medusa.prank(user);
        permit2.approve(token, address(router), type(uint160).max, type(uint48).max);
        medusa.prank(user);
        permit2.approve(token, address(batchRouter), type(uint160).max, type(uint48).max);
        medusa.prank(user);
        permit2.approve(token, address(compositeLiquidityRouter), type(uint160).max, type(uint48).max);
    }

    function _create3(bytes memory constructorArgs, bytes memory bytecode, bytes32 salt) private returns (address) {
        return CREATE3.deploy(salt, abi.encodePacked(bytecode, constructorArgs), 0);
    }
}
