// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RateLimiter} from "./RateLimiter.sol";

contract SingleTokenInOutRateLimiter {
    using RateLimiter for RateLimiter.Bucket;

    RateLimiter.Bucket private inTokenBucket;
    RateLimiter.Bucket private outTokenBucket;

    event TokenTransferLimitConfigUpdated(
        address indexed token,
        bool indexed isInput,
        uint128 tokenTransferCapacity,
        uint128 tokenTransferRate,
        bool isDisabled
    );

    constructor(
        address _token,
        RateLimiter.InitBucket memory _inTokenBucket,
        RateLimiter.InitBucket memory _outTokenBucket
    ) {
        inTokenBucket.init(_inTokenBucket);

        emit TokenTransferLimitConfigUpdated(
            _token,
            true,
            _inTokenBucket.capacity,
            _inTokenBucket.rate,
            false
        );

        outTokenBucket.init(_outTokenBucket);

        emit TokenTransferLimitConfigUpdated(
            _token,
            false,
            _outTokenBucket.capacity,
            _outTokenBucket.rate,
            false
        );
    }

    function getTokenTransferLimitBucket(
        bool _isInput
    ) public view returns (RateLimiter.Bucket memory) {
        RateLimiter.Bucket storage tokenBucket = getTokenBucket(_isInput);

        return
            RateLimiter.Bucket({
                tokens: uint128(tokenBucket.getAvailableTokens()),
                lastUpdated: uint32(block.timestamp),
                capacity: tokenBucket.capacity,
                rate: tokenBucket.rate,
                isDisabled: tokenBucket.isDisabled
            });
    }

    function enforceTokenTransferLimit(
        bool _isInput,
        uint256 _amount
    ) internal {
        getTokenBucket(_isInput).consume(_amount);
    }

    function _updateTokenTransferLimitConfig(
        address _token,
        bool _isInput,
        uint128 _tokenTransferCapacity,
        uint128 _tokenTransferRate,
        bool _isDisabled
    ) internal {
        getTokenBucket(_isInput).updateConfig(
            _tokenTransferCapacity,
            _tokenTransferRate,
            _isDisabled
        );

        emit TokenTransferLimitConfigUpdated(
            _token,
            _isInput,
            _tokenTransferCapacity,
            _tokenTransferRate,
            _isDisabled
        );
    }

    function getTokenBucket(
        bool _isInput
    ) private view returns (RateLimiter.Bucket storage) {
        return _isInput ? inTokenBucket : outTokenBucket;
    }
}
