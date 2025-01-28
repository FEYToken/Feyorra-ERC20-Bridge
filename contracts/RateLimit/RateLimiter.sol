// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// `capacity` defines the maximum number of tokens the bucket can hold at any given time.
// for rate limiting rarely require the larger range of `uint256`.
// Consuming an amount larger than `uint128` (`2^128 - 1`) in a single operation is considered abnormal
// because such a high value would typically exceed practical use cases for rate-limiting systems.
// If consumption of excessively large values is attempted, it may indicate misuse or a misconfiguration
library RateLimiter {
    struct InitBucket {
        uint128 capacity;
        uint128 rate;
    }

    struct Bucket {
        uint128 tokens;
        uint32 lastUpdated;
        uint128 capacity;
        uint128 rate;
        bool isDisabled;
    }

    modifier validateRateCapacity(uint128 capacity, uint128 rate) {
        require(rate > 0 && rate < capacity, "Invalid rate or capacity");
        _;
    }

    function init(
        Bucket storage bucket,
        InitBucket memory _initBucket
    ) internal validateRateCapacity(_initBucket.capacity, _initBucket.rate) {
        bucket.capacity = _initBucket.capacity;
        bucket.rate = _initBucket.rate;
        bucket.tokens = _initBucket.capacity;
        bucket.lastUpdated = uint32(block.timestamp);
    }

    function consume(Bucket storage bucket, uint256 amount) internal {
        if (amount == 0 || bucket.isDisabled) return;

        uint256 availableTokens = getAvailableTokens(bucket);
        require(availableTokens >= amount, "Rate limit exceeded");

        bucket.tokens = uint128(availableTokens - amount);
        bucket.lastUpdated = uint32(block.timestamp);
    }

    function getAvailableTokens(
        Bucket storage bucket
    ) internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - bucket.lastUpdated;
        if (timeElapsed == 0) {
            return bucket.tokens;
        }

        uint256 newTokens = uint256(bucket.tokens) + timeElapsed * bucket.rate;
        return Math.min(bucket.capacity, newTokens);
    }

    function updateConfig(
        Bucket storage bucket,
        uint128 _capacity,
        uint128 _rate,
        bool _isDisabled
    ) internal validateRateCapacity(_capacity, _rate) {
        bucket.capacity = _capacity;
        bucket.rate = _rate;
        bucket.isDisabled = _isDisabled;
    }
}
