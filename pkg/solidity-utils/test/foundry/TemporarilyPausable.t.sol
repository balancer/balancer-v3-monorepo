// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import "../../contracts/helpers/TemporarilyPausable.sol";
import "../../contracts/test/TemporarilyPausableMock.sol";
import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/ITemporarilyPausable.sol";

contract BaseTest is Test {
    TemporarilyPausableMock internal pausable;
    uint256 internal constant MONTH = 30 days;
    uint256 internal constant PAUSE_WINDOW_DURATION = MONTH * 3;
    uint256 internal constant BUFFER_PERIOD_DURATION = MONTH;
}

contract TemporarilyPausableTest is BaseTest {
    function setUp() public {
        pausable = new TemporarilyPausableMock(PAUSE_WINDOW_DURATION, BUFFER_PERIOD_DURATION);
    }

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

contract TemporarilyPausableAfterPauseWindowTest is BaseTest {
    function setUp() public {
        pausable = new TemporarilyPausableMock(PAUSE_WINDOW_DURATION, BUFFER_PERIOD_DURATION);
        skip(PAUSE_WINDOW_DURATION);
    }

    function itIsForeverUnpaused() public {
        itIsUnpaused();
        canNotBeUnpausedAgain();
        canNotBePausedInTheFuture();
        canNotBePaused();
    }

    function itIsUnpaused() public {
        assertEq(pausable.paused(), false);
    }

    function canNotBeUnpausedAgain() public {
        vm.expectRevert(ITemporarilyPausable.AlreadyUnpaused.selector);
        pausable.unpause();
    }

    function canNotBePausedInTheFuture() public {
        skip(MONTH * 12);
        vm.expectRevert(ITemporarilyPausable.PauseWindowExpired.selector);
        pausable.pause();
    }

    function canNotBePaused() public {
        vm.expectRevert(ITemporarilyPausable.PauseWindowExpired.selector);
        pausable.pause();
    }

    // after the pause window end date has been reached

    // when unpaused
    // before the buffer period end date
    function testBeforeBufferPeriodEndDateItIsForeverUnpaused() public {
        skip(BUFFER_PERIOD_DURATION / 2);
        itIsForeverUnpaused();
    }

    // after the buffer period end date
    function testAfterBufferPeriodEndDateItIsForeverUnpaused() public {
        skip(BUFFER_PERIOD_DURATION);
        itIsForeverUnpaused();
    }
}

contract TemporarilyPausableAfterPauseWindowWhenPausedTest is BaseTest {
    function setUp() public {
        pausable = new TemporarilyPausableMock(PAUSE_WINDOW_DURATION, BUFFER_PERIOD_DURATION);
        pausable.pause();
        skip(PAUSE_WINDOW_DURATION);
    }

    // when paused
    // before the buffer period end date
    function testItIsPaused() public {
        skip(BUFFER_PERIOD_DURATION / 2);
        assertEq(pausable.paused(), true);
    }

    function testCanNotBePausedAgain() public {
        skip(BUFFER_PERIOD_DURATION / 2);
        vm.expectRevert(ITemporarilyPausable.AlreadyPaused.selector);
        pausable.pause();
    }

    function testCanBeUnpaused() public {
        skip(BUFFER_PERIOD_DURATION / 2);
        pausable.unpause();
        assertEq(pausable.paused(), false);
    }

    function testCanNotBeUnpausedAndThenPaused() public {
        skip(BUFFER_PERIOD_DURATION / 2);
        pausable.unpause();
        assertEq(pausable.paused(), false);
        vm.expectRevert(ITemporarilyPausable.PauseWindowExpired.selector);
        pausable.pause();
    }

    // after the buffer period end date
    function testItIsUnpaused() public {
        skip(BUFFER_PERIOD_DURATION + 1);
        assertEq(pausable.paused(), false);
    }

    function testCanNotBeUnpausedAgain() public {
        skip(BUFFER_PERIOD_DURATION + 1);
        vm.expectRevert(ITemporarilyPausable.AlreadyUnpaused.selector);
        pausable.unpause();
    }

    function testCanNotBePaused() public {
        skip(BUFFER_PERIOD_DURATION + 1);
        vm.expectRevert(ITemporarilyPausable.PauseWindowExpired.selector);
        pausable.pause();
    }
}
