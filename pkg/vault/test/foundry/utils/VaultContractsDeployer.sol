// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { HooksConfigLibMock } from "@balancer-labs/v3-vault/contracts/test/HooksConfigLibMock.sol";
import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

import { BaseHooksMock } from "../../../contracts/test/BaseHooksMock.sol";
import { BasicAuthorizerMock } from "../../../contracts/test/BasicAuthorizerMock.sol";
import { BatchRouterMock } from "../../../contracts/test/BatchRouterMock.sol";
import { ERC20MultiTokenMock } from "../../../contracts/test/ERC20MultiTokenMock.sol";
import { LinearBasePoolMathMock } from "../../../contracts/test/LinearBasePoolMathMock.sol";
import { ProtocolFeeController } from "../../../contracts/ProtocolFeeController.sol";
import { VaultExtensionMock } from "../../../contracts/test/VaultExtensionMock.sol";
import { VaultAdminMock } from "../../../contracts/test/VaultAdminMock.sol";
import { VaultMock } from "../../../contracts/test/VaultMock.sol";
import { ProtocolFeeControllerMock } from "../../../contracts/test/ProtocolFeeControllerMock.sol";
import { PoolFactoryMock } from "../../../contracts/test/PoolFactoryMock.sol";
import { PoolMock } from "../../../contracts/test/PoolMock.sol";
import { PoolHooksMock } from "../../../contracts/test/PoolHooksMock.sol";
import { PoolMockFlexibleInvariantRatio } from "../../../contracts/test/PoolMockFlexibleInvariantRatio.sol";
import { RateProviderMock } from "../../../contracts/test/RateProviderMock.sol";
import { RouterCommonMock } from "../../../contracts/test/RouterCommonMock.sol";
import { RouterMock } from "../../../contracts/test/RouterMock.sol";

contract VaultContractsDeployer is BaseContractsDeployer {
    string artifactsRootDir;

    constructor() {
        // if this artifacts/@balancer-labs/v3-vault exists, it means we are running outside of this repo
        if (vm.exists("artifacts/@balancer-labs/v3-vault")) {
            artifactsRootDir = "artifacts/@balancer-labs/v3-vault/";
        } else {
            artifactsRootDir = "artifacts/";
        }
    }

    function deployBaseHookMock() internal returns (BaseHooksMock) {
        if (reusingArtifacts) {
            return BaseHooksMock(deployCode(_computePath(type(BaseHooksMock).name)));
        } else {
            return new BaseHooksMock();
        }
    }

    function deployBasicAuthorizerMock() internal returns (BasicAuthorizerMock) {
        if (reusingArtifacts) {
            return BasicAuthorizerMock(deployCode(_computePath(type(BasicAuthorizerMock).name)));
        } else {
            return new BasicAuthorizerMock();
        }
    }

    function deployBatchRouterMock(IVault vault, IWETH weth, IPermit2 permit2) internal returns (BatchRouterMock) {
        if (reusingArtifacts) {
            return
                BatchRouterMock(
                    payable(deployCode(_computePath(type(BatchRouterMock).name), abi.encode(vault, weth, permit2)))
                );
        } else {
            return new BatchRouterMock(vault, weth, permit2);
        }
    }

    function deployERC20MultiTokenMock() internal returns (ERC20MultiTokenMock) {
        if (reusingArtifacts) {
            return ERC20MultiTokenMock(deployCode(_computePath(type(ERC20MultiTokenMock).name)));
        } else {
            return new ERC20MultiTokenMock();
        }
    }

    function deployHooksConfigLibMock() internal returns (HooksConfigLibMock) {
        if (reusingArtifacts) {
            return HooksConfigLibMock(deployCode(_computePath(type(HooksConfigLibMock).name)));
        } else {
            return new HooksConfigLibMock();
        }
    }

    function deployLinearBasePoolMathMock() internal returns (LinearBasePoolMathMock) {
        if (reusingArtifacts) {
            return LinearBasePoolMathMock(deployCode(_computePath(type(LinearBasePoolMathMock).name)));
        } else {
            return new LinearBasePoolMathMock();
        }
    }

    function deployVaultMock(uint256 minTradeAmount, uint256 minWrapAmount) internal returns (IVaultMock) {
        IAuthorizer authorizer = deployBasicAuthorizerMock();
        bytes32 salt = bytes32(0);
        VaultMock vault = VaultMock(payable(CREATE3.getDeployed(salt)));

        VaultAdminMock vaultAdmin;
        VaultExtensionMock vaultExtension;
        ProtocolFeeController protocolFeeController;
        bytes memory vaultMockBytecode;

        if (reusingArtifacts) {
            vaultMockBytecode = vm.getCode(_computePath(type(VaultMock).name));
            vaultAdmin = VaultAdminMock(
                payable(
                    deployCode(
                        _computePath(type(VaultAdminMock).name),
                        abi.encode(vault, 90 days, 30 days, minTradeAmount, minWrapAmount)
                    )
                )
            );
            vaultExtension = VaultExtensionMock(
                payable(deployCode(_computePath(type(VaultExtensionMock).name), abi.encode(vault, vaultAdmin)))
            );
            protocolFeeController = ProtocolFeeControllerMock(
                deployCode(_computePath(type(ProtocolFeeControllerMock).name), abi.encode(vault))
            );
        } else {
            vaultMockBytecode = type(VaultMock).creationCode;
            vaultAdmin = new VaultAdminMock(IVault(payable(vault)), 90 days, 30 days, minTradeAmount, minWrapAmount);
            vaultExtension = new VaultExtensionMock(IVault(payable(vault)), vaultAdmin);
            protocolFeeController = new ProtocolFeeControllerMock(IVault(payable(vault)));
        }

        _create3(abi.encode(vaultExtension, authorizer, protocolFeeController), vaultMockBytecode, salt);
        return IVaultMock(address(vault));
    }

    function deployPoolFactoryMock(IVault vault, uint32 pauseWindowDuration) internal returns (PoolFactoryMock) {
        if (reusingArtifacts) {
            return
                PoolFactoryMock(
                    deployCode(_computePath(type(PoolFactoryMock).name), abi.encode(vault, pauseWindowDuration))
                );
        } else {
            return new PoolFactoryMock(vault, pauseWindowDuration);
        }
    }

    function deployPoolHooksMock(IVault vault) internal returns (PoolHooksMock) {
        if (reusingArtifacts) {
            return PoolHooksMock(deployCode(_computePath(type(PoolHooksMock).name), abi.encode(vault)));
        } else {
            return new PoolHooksMock(vault);
        }
    }

    function deployPoolMock(IVault vault, string memory name, string memory symbol) internal returns (PoolMock) {
        if (reusingArtifacts) {
            return PoolMock(deployCode(_computePath(type(PoolMock).name), abi.encode(vault, name, symbol)));
        } else {
            return new PoolMock(vault, name, symbol);
        }
    }

    function deployPoolMockFlexibleInvariantRatio(
        IVault vault,
        string memory name,
        string memory symbol
    ) internal returns (PoolMockFlexibleInvariantRatio) {
        if (reusingArtifacts) {
            return
                PoolMockFlexibleInvariantRatio(
                    deployCode(_computePath(type(PoolMockFlexibleInvariantRatio).name), abi.encode(vault, name, symbol))
                );
        } else {
            return new PoolMockFlexibleInvariantRatio(vault, name, symbol);
        }
    }

    function deployRateProviderMock() internal returns (RateProviderMock) {
        if (reusingArtifacts) {
            return RateProviderMock(deployCode(_computePath(type(RateProviderMock).name)));
        } else {
            return new RateProviderMock();
        }
    }

    function deployRouterCommonMock(IVault vault, IWETH weth, IPermit2 permit2) internal returns (RouterCommonMock) {
        if (reusingArtifacts) {
            return
                RouterCommonMock(
                    payable(deployCode(_computePath(type(RouterCommonMock).name), abi.encode(vault, weth, permit2)))
                );
        } else {
            return new RouterCommonMock(vault, weth, permit2);
        }
    }

    function deployRouterMock(IVault vault, IWETH weth, IPermit2 permit2) internal returns (RouterMock) {
        if (reusingArtifacts) {
            return
                RouterMock(payable(deployCode(_computePath(type(RouterMock).name), abi.encode(vault, weth, permit2))));
        } else {
            return new RouterMock(vault, weth, permit2);
        }
    }

    function _computePath(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/test/", name, ".sol/", name, ".json"));
    }

    function _create3(bytes memory constructorArgs, bytes memory bytecode, bytes32 salt) private returns (address) {
        return CREATE3.deploy(salt, abi.encodePacked(bytecode, constructorArgs), 0);
    }
}
