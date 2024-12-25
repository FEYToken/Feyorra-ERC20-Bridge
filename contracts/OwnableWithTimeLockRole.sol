// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)
// Upgraded to OwnableWithTimeLock

pragma solidity ^0.8.24;

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableWithTimeLockRole {
    address private _immediateOwner;
    address private _timeLockedOwner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner,
        bool indexed isTimeLock
    );

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     * @notice It is the deployer's responsibility to ensure that `_timeLockedOwner`
     * is set to a TimelockController (or another contract) which enforces the
     * actual time-lock mechanics. This contract itself does not implement any
     * built-in delay logic; it simply provides a separate ownership slot intended
     * for a contract address that manages time-locking externally.
     */
    constructor(address immediateOwner_, address timeLockedOwner_) {
        _transferOwnership(immediateOwner_, false);
        _transferOwnership(timeLockedOwner_, true);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner(bool isTimeLock) {
        _checkOwner(isTimeLock);
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner(bool isTimeLock) public view returns (address) {
        return isTimeLock ? _timeLockedOwner : _immediateOwner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner(bool isTimeLock) internal view {
        if (owner(isTimeLock) != msg.sender) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership(bool isTimeLock) public virtual onlyOwner(true) {
        _transferOwnership(address(0x0), isTimeLock);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(
        address newOwner,
        bool isTimeLock
    ) public onlyOwner(true) {
        if (newOwner == address(0x0)) {
            revert OwnableInvalidOwner(address(0x0));
        }
        _transferOwnership(newOwner, isTimeLock);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner, bool isTimeLock) internal {
        address oldOwner;

        if (isTimeLock) {
            oldOwner = _timeLockedOwner;
            _timeLockedOwner = newOwner;
        } else {
            oldOwner = _immediateOwner;
            _immediateOwner = newOwner;
        }

        emit OwnershipTransferred(oldOwner, newOwner, isTimeLock);
    }
}
