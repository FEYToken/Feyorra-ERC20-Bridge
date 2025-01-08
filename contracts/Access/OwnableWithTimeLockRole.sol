// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)
// Upgraded to OwnableWithTimeLockRole

pragma solidity ^0.8.24;

/**
 * @dev This contract provides a dual-ownership model:
 *
 * - `_immediateOwner` for direct (immediate) operations.
 * - `_timeLockedOwner` intended for a contract-based owner (e.g., a TimelockController)
 *   that enforces a delay mechanism externally.
 *
 * Important: This contract does NOT implement any built-in time-lock logic by itself.
 * It only offers two separate ownership slots. Actual time-locking (e.g., a 48-hour delay)
 * must be managed by the contract set as `_timeLockedOwner` if desired.
 *
 * The initial owners (both `_immediateOwner` and `_timeLockedOwner`) are set by the deployer
 * in the constructor. Only the address designated as `_timeLockedOwner` (i.e., `owner(true)`)
 * has the authority to call `transferOwnership` and `renounceOwnership` in this implementation.
 */
abstract contract OwnableWithTimeLockRole {
    /**
     * @dev The immediate owner with full, direct privileges for any functions
     *      that check `onlyOwner(false)`.
     */
    address private _immediateOwner;

    /**
     * @dev The time-locked owner, which is expected to be a contract address
     *      (e.g., a TimelockController) if you want external enforcement
     *      of delayed operations. Functions checking `onlyOwner(true)` can
     *      only be invoked by `_timeLockedOwner`.
     */
    address private _timeLockedOwner;

    /**
     * @dev Thrown when `msg.sender` is not the required owner (either the immediate
     *      or the time-locked owner, depending on context).
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev Thrown when attempting to set an owner to the zero address.
     */
    error OwnableInvalidOwner(address owner);

    /**
     * @dev Emitted when ownership changes from `previousOwner` to `newOwner`.
     *      The `isTimeLock` flag indicates whether the change affected
     *      `_timeLockedOwner` (true) or `_immediateOwner` (false).
     */
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner,
        bool indexed isTimeLock
    );

    /**
     * @dev Sets `_immediateOwner` and `_timeLockedOwner` at deployment.
     *
     * @notice It is the deployer's responsibility to ensure that `_timeLockedOwner`
     * is set to a TimelockController (or another contract) which enforces the
     * actual time-lock mechanics. This contract itself does not implement any
     * built-in delay logic; it simply provides a separate ownership slot intended
     * for a contract address that manages time-locking externally.
     */
    constructor(address immediateOwner_, address timeLockedOwner_) {
        require(
            immediateOwner_ != address(0x0) && timeLockedOwner_ != address(0x0),
            "OwnableWithTimeLockRole: owner cannot be the zero address"
        );

        _transferOwnership(immediateOwner_, false);
        _transferOwnership(timeLockedOwner_, true);
    }

    /**
     * @dev Modifier restricting access to either `_immediateOwner` (if `isTimeLock = false`)
     *      or `_timeLockedOwner` (if `isTimeLock = true`).
     */
    modifier onlyOwner(bool isTimeLock) {
        _checkOwner(isTimeLock);
        _;
    }

    /**
     * @dev Returns the current owner. If `isTimeLock = true`, returns `_timeLockedOwner`;
     *      otherwise, returns `_immediateOwner`.
     */
    function owner(bool isTimeLock) public view returns (address) {
        return isTimeLock ? _timeLockedOwner : _immediateOwner;
    }

    /**
     * @dev Internal check for ownership:
     *      - If `isTimeLock = true`, require `msg.sender == _timeLockedOwner`.
     *      - Otherwise, require `msg.sender == _immediateOwner`.
     */
    function _checkOwner(bool isTimeLock) internal view {
        if (owner(isTimeLock) != msg.sender) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
    }

    /**
     * @dev Renounces ownership by setting the time-locked owner to the zero address.
     *      After this call, `onlyOwner(true)` functions are permanently disabled.
     *
     * Can only be called by the current `_timeLockedOwner`.
     *
     * NOTE: This leaves the contract without a time-locked owner, thereby disabling
     * any functionality that is exclusive to the `_timeLockedOwner`.
     */
    function renounceOwnership(bool isTimeLock) public virtual onlyOwner(true) {
        _transferOwnership(address(0x0), isTimeLock);
    }

    /**
     * @dev Transfers ownership to `newOwner`. If `isTimeLock = true`,
     *      updates `_timeLockedOwner`. Otherwise updates `_immediateOwner`.
     *
     * Can only be called by the current `_timeLockedOwner`.
     *
     * @param newOwner    The address of the new owner.
     * @param isTimeLock  Whether we are modifying the `_timeLockedOwner` (true)
     *                    or `_immediateOwner` (false).
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
     * @dev Internal function that switches either `_immediateOwner` or `_timeLockedOwner`
     *      to `newOwner` based on the `isTimeLock` flag. Emits an {OwnershipTransferred} event.
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
