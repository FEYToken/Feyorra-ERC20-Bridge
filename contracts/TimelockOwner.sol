// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract TimelockOwner is TimelockController {
    constructor(
        uint256 minDelaySeconds,
        address[] memory proposers,
        address[] memory executors
    ) TimelockController(minDelaySeconds, proposers, executors, address(0x0)) {}
}
