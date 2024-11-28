// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.24;

abstract contract RandomBytes32Generator {
    uint256 private nonce;

    function generateRandomBytes32() internal returns (bytes32) {
        nonce++;
        return
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    msg.sender,
                    nonce,
                    address(this)
                )
            );
    }
}
