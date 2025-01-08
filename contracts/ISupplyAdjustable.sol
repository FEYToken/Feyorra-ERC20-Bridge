// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface ISupplyAdjustable {
    function burn(uint256 value) external;
    function mint(uint256 value) external;
}
