// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RateLimiter} from "./RateLimiter.sol";

contract SingleTokenRateLimiter {
    using RateLimiter for RateLimiter.Bucket;

    RateLimiter.Bucket private tokenBucket;

    event TokenTransferLimitConfigUpdated(
        address indexed token,
        uint128 tokenTransferCapacity,
        uint128 tokenTransferRate,
        bool isDisabled
    );

    constructor(
        address _token,
        uint128 _tokenTransferCapacity,
        uint128 _tokenTransferRate
    ) {
        tokenBucket.init(_tokenTransferCapacity, _tokenTransferRate);

        emit TokenTransferLimitConfigUpdated(
            _token,
            _tokenTransferCapacity,
            _tokenTransferRate,
            tokenBucket.isDisabled
        );
    }

    function getTokenTransferLimitBucket()
        public
        view
        returns (RateLimiter.Bucket memory)
    {
        return
            RateLimiter.Bucket({
                tokens: uint128(tokenBucket.getAvailableTokens()),
                lastUpdated: uint32(block.timestamp),
                capacity: tokenBucket.capacity,
                rate: tokenBucket.rate,
                isDisabled: tokenBucket.isDisabled
            });
    }

    function enforceTokenTransferLimit(uint256 _amount) internal {
        tokenBucket.consume(_amount);
    }

    function _updateTokenTransferLimitConfig(
        address _token,
        uint128 _tokenTransferCapacity,
        uint128 _tokenTransferRate,
        bool _isDisabled
    ) internal {
        tokenBucket.updateConfig(
            _tokenTransferCapacity,
            _tokenTransferRate,
            _isDisabled
        );

        emit TokenTransferLimitConfigUpdated(
            _token,
            _tokenTransferCapacity,
            _tokenTransferRate,
            _isDisabled
        );
    }
}
