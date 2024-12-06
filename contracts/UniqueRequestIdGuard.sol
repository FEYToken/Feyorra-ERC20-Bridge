// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.24;

abstract contract UniqueRequestIdGuard {
    mapping(bytes32 => bool) private requestIdProcessed;

    modifier onlyNotProcessedRequestId(bytes32 _requestId) {
        require(
            !requestIdProcessed[_requestId],
            "Request ID already processed"
        );
        requestIdProcessed[_requestId] = true;
        _;
    }
}
