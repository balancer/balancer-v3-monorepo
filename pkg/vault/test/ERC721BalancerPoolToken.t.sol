// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import "../contracts/ERC721BalancerPoolToken.sol";

contract BaseTest is Test {
    TemporarilyPausableMock internal pausable;
    uint256 internal constant MONTH = 30 days;
    uint256 internal constant PAUSE_WINDOW_DURATION = MONTH * 3;
    uint256 internal constant BUFFER_PERIOD_DURATION = MONTH;
}

contract ERC721BalancerPoolTokenTest is BaseTest {
    function setUp() public {}

    // initialization

    function testInitWithNonZeroParams() public {
        pausable = new TemporarilyPausableMock(MONTH, MONTH);
        assertEq(pausable.paused(), false);
        (uint256 pauseWindowEndTime, uint256 bufferPeriodEndTime) = pausable.getPauseEndTimes();
        assertEq(pauseWindowEndTime, block.timestamp + MONTH);
        assertEq(bufferPeriodEndTime, block.timestamp + MONTH + MONTH);
    }

    function testInitWithZeroParams() public {
        pausable = new TemporarilyPausableMock(0, 0);
        assertEq(pausable.paused(), false);
        (uint256 pauseWindowEndTime, uint256 bufferPeriodEndTime) = pausable.getPauseEndTimes();
        assertEq(pauseWindowEndTime, block.timestamp);
        assertEq(bufferPeriodEndTime, block.timestamp);
    }

    function testInitMaxPauseWindow() public {
        vm.expectRevert(ITemporarilyPausable.PauseWindowDurationTooLarge.selector);
        pausable = new TemporarilyPausableMock(PausableConstants.MAX_PAUSE_WINDOW_DURATION + 1, 0);
    }

    function testInitMaxBufferPeriod() public {
        vm.expectRevert(ITemporarilyPausable.BufferPeriodDurationTooLarge.selector);
        pausable = new TemporarilyPausableMock(MONTH, PausableConstants.MAX_BUFFER_PERIOD_DURATION + 1);
    }

    // pause/unpause

    // before the pause window end date has been reached

    function testCanBePausedBeforePauseWindow() public {
        pausable.pause();
        assertEq(pausable.paused(), true);
    }

    function testCanNotBePausedTwiceBeforePauseWindow() public {
        pausable.pause();
        vm.expectRevert(ITemporarilyPausable.AlreadyPaused.selector);
        pausable.pause();
    }

    function testCanNotBeUnpausedTwiceBeforePauseWindow() public {
        vm.expectRevert(ITemporarilyPausable.AlreadyUnpaused.selector);
        pausable.unpause();
    }

    function testCanBePausedAndUnpausedBeforePauseWindow() public {
        pausable.pause();
        assertEq(pausable.paused(), true);

        pausable.unpause();
        assertEq(pausable.paused(), false);
    }
}
