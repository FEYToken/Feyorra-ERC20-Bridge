// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.24;

abstract contract UniqueRequestIdGuard {
    mapping(bytes32 => bool) private requestIdProcessed;

    error RequestIdAlreadyProcessed(bytes32 requestId);

    modifier onlyNotProcessedRequestId(bytes32 _requestId) {
        if (requestIdProcessed[_requestId]) {
            revert RequestIdAlreadyProcessed(_requestId);
        }

        requestIdProcessed[_requestId] = true;
        _;
    }
}
