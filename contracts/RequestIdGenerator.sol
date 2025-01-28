// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.24;

abstract contract RequestIdGenerator {
    uint256 private nonce;

    function getRequestId(
        uint64 _destinationChainSelector,
        uint256 _amount,
        bytes calldata _receiverBridge,
        bytes calldata _recipient
    ) internal returns (bytes32, uint256) {
        nonce++;
        return (
            keccak256(
                abi.encode(
                    nonce,
                    block.chainid,
                    block.timestamp,
                    address(this),
                    _destinationChainSelector,
                    _receiverBridge,
                    _amount,
                    _recipient
                )
            ),
            nonce
        );
    }
}
