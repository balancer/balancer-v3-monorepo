// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFeeCollector } from "../IFeeCollector.sol";

contract FeeCollectorMock is IFeeCollector {
    uint256 private _fee;
    IERC20 private _target;
    address private _owner;
    address private _emergency_owner;
    address private _cowSwapBurner;

    constructor(uint256 fee_, IERC20 target_, address owner_, address emergency_owner_) {
        _fee = fee_;
        _target = target_;
        _owner = owner_;
        _emergency_owner = emergency_owner_;
    }

    function setCowSwapBurner(address cowSwapBurner_) external {
        _cowSwapBurner = cowSwapBurner_;
    }

    function burn(address[] memory coins, address receiver) external {
        (bool success, ) = _cowSwapBurner.call(abi.encodeWithSignature("burn(address[],address)", coins, receiver));
        require(success, "FeeCollectorMock: burn failed");
    }

    function setFee(uint256 fee_) external {
        _fee = fee_;
    }

    function fee(Epoch epoch, uint256 timestamp) external view returns (uint256) {
        return _fee;
    }

    function setTarget(IERC20 target_) external {
        _target = target_;
    }

    function target() external view returns (IERC20) {
        return _target;
    }

    function setOwner(address owner_) external {
        _owner = owner_;
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function setEmergencyOwner(address emergency_owner_) external {
        _emergency_owner = emergency_owner_;
    }

    function emergency_owner() external view returns (address) {
        return _emergency_owner;
    }

    function epoch_time_frame(Epoch epoch, uint256 timestamp) external pure returns (uint256, uint256) {
        return (type(uint32).max, type(uint32).max);
    }

    function can_exchange(IERC20[] memory coins) external pure returns (bool) {
        return true;
    }

    function transfer(Transfer[] memory transfers) external {
        for (uint256 i = 0; i < transfers.length; i++) {
            transfers[i].coin.transfer(transfers[i].to, transfers[i].amount);
        }
    }
}
