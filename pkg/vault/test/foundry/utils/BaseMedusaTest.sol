// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { DeployPermit2 } from "permit2/test/utils/DeployPermit2.sol";

import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IStdMedusaCheats } from "@balancer-labs/v3-interfaces/contracts/test/IStdMedusaCheats.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";

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

contract BaseMedusaTest {
    IStdMedusaCheats internal medusa = IStdMedusaCheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

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

    uint256 internal constant DEFAULT_USER_BALANCE = 1e9 * 1e18;

    // Set alice,bob and lp to addresses of medusa.json "senderAddresses" property
    address internal alice = address(0x10000);
    address internal bob = address(0x20000);
    address internal lp = address(0x30000);

    ERC20TestToken internal dai;
    ERC20TestToken internal usdc;
    WETHTestToken internal weth;

    // Create Permit2
    // Create Vault/Routers/etc
    // Set permissions for users

    constructor() {
        dai = _createERC20TestToken("DAI", "DAI", 18);
        usdc = _createERC20TestToken("USDC", "USDC", 18);
        weth = new WETHTestToken();

        // The only function used by _mintTokenToUsers is mint, which has the same signature as ERC20TestToken. So,
        // cast weth as ERC20TestToken to use the same funtion.
        _mintTokenToUsers(ERC20TestToken(address(weth)));

        DeployPermit2 _deployPermit2 = new DeployPermit2();
        permit2 = IPermit2(_deployPermit2.deployPermit2());

        _deployVaultMock(0, 0);

        router = new RouterMock(IVault(address(vault)), weth, permit2);
        batchRouter = new BatchRouterMock(IVault(address(vault)), weth, permit2);
        compositeLiquidityRouter = new CompositeLiquidityRouterMock(IVault(address(vault)), weth, permit2);
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
        feeController = new ProtocolFeeControllerMock(IVault(payable(address(newVault))));

        _create3(abi.encode(vaultExtension, authorizer, feeController), vaultMockBytecode, salt);

        address poolFactoryMock = newVault.getPoolFactoryMock();
        factoryMock = PoolFactoryMock(poolFactoryMock);

        vault = IVaultMock(address(newVault));
    }

    function _create3(bytes memory constructorArgs, bytes memory bytecode, bytes32 salt) private returns (address) {
        return CREATE3.deploy(salt, abi.encodePacked(bytecode, constructorArgs), 0);
    }
}
