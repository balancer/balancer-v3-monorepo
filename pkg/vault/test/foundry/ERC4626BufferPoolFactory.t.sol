// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { VaultMockDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultMockDeployer.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
import { ERC4626BufferPoolFactory } from "@balancer-labs/v3-vault/contracts/factories/ERC4626BufferPoolFactory.sol";
import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { ERC4626BufferPool } from "../../contracts/ERC4626BufferPool.sol";

contract ERC4626BufferPoolFactoryTest is Test {
    VaultMock vault;
    ERC4626BufferPoolFactory factory;
    ERC20TestToken baseToken;
    ERC4626TestToken wrappedToken;

    address alice = vm.addr(1);

    function setUp() public {
        vault = VaultMockDeployer.deploy();
        factory = new ERC4626BufferPoolFactory(IVault(address(vault)), 365 days);
        baseToken = new ERC20TestToken("Token A", "TKNA", 18);
        wrappedToken = new ERC4626TestToken(baseToken, "WrappedToken A", "WTKNA", 18);
    }

    // Used to comply with the _isValidWrappedToken() check for the test token
    function _increaseERC4626TotalAssets() internal {
        baseToken.mint(alice, 100e18);
        vm.startPrank(alice);
        baseToken.approve(address(wrappedToken), 100e18);
        wrappedToken.deposit(100e18, alice);
        vm.stopPrank();
    }

    function testFactoryPausedState() public {
        uint256 pauseWindowDuration = factory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }

    function testBufferPoolGetter_Fuzz(bytes32 salt) public {
        _increaseERC4626TotalAssets();
        ERC4626BufferPool bufferPool = ERC4626BufferPool(factory.create(wrappedToken, address(0), salt));

        address fetchedPool = factory.getBufferPool(wrappedToken);

        assertEq(
            address(bufferPool),
            address(fetchedPool),
            "getBufferPool is fetching a buffer pool different from the one being created"
        );
    }

    function testPoolUniqueness__Fuzz(bytes32 firstSalt, bytes32 secondSalt) public {
        vm.assume(firstSalt != secondSalt);

        _increaseERC4626TotalAssets();
        ERC4626BufferPool(factory.create(wrappedToken, address(0), firstSalt));

        address fetchedPool = factory.getBufferPool(wrappedToken);

        assertNotEq(fetchedPool, address(0), "Pool has not been registered into the _bufferPools mapping correctly");

        // Trying to create the same buffer pool with different salt should revert
        vm.expectRevert(ERC4626BufferPoolFactory.BufferPoolAlreadyExists.selector);
        ERC4626BufferPool(factory.create(wrappedToken, address(0), secondSalt));
    }
}
