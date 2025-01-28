// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Pausable} from "./Access/Pausable.sol";

abstract contract ChainManager is Pausable {
    // store in a single storage slot: 20 (hash) + 11 (fees) + 1 (flags) = 32 bytes
    struct Chain {
        bytes20 bridgeAddressHash;
        uint88 fees;
        uint8 flags; // 0: isSource, 1: isDestination, 2: isCustom
    }

    mapping(uint64 => Chain) public chains;

    event ChainUpdated(
        uint64 indexed chainSelector,
        bytes bridgeAddress,
        uint88 fees,
        bool isSource,
        bool isDestination,
        bool isCustom
    );

    event ChainDeleted(uint64 indexed chainSelector);

    function deleteChain(
        uint64 _chainSelector
    ) external whenNotPaused onlyOwner(false) {
        delete chains[_chainSelector];
        emit ChainDeleted(_chainSelector);
    }

    function updateChain(
        uint64 _chainSelector,
        bytes calldata _bridgeAddress,
        uint88 _fees,
        bool _isSource,
        bool _isDestination,
        bool _isCustom
    ) external whenNotPaused onlyOwner(false) {
        require(
            _bridgeAddress.length > 0,
            "ChainManager: invalid bridge address"
        );

        if (_isCustom) {
            require(_fees > 0, "ChainManager: invalid fees for custom chain");
        }

        uint8 flags = 0;

        flags = setFlag(flags, 0, _isSource);
        flags = setFlag(flags, 1, _isDestination);
        flags = setFlag(flags, 2, _isCustom);

        chains[_chainSelector] = Chain({
            bridgeAddressHash: ripemd160(_bridgeAddress),
            fees: _fees,
            flags: flags
        });

        emit ChainUpdated({
            chainSelector: _chainSelector,
            bridgeAddress: _bridgeAddress,
            fees: _fees,
            isSource: _isSource,
            isDestination: _isDestination,
            isCustom: _isCustom
        });
    }

    function setFlag(
        uint8 _flags,
        uint8 _position,
        bool _value
    ) private pure returns (uint8) {
        return
            uint8(
                _value
                    ? (_flags | (1 << _position))
                    : (_flags & ~(1 << _position))
            );
    }

    function validateChain(
        uint64 _chainSelector,
        bytes20 _bridgeAddressRipemd160Hash,
        bool _isSource,
        bool _isCustom
    ) internal view {
        Chain storage chain = chains[_chainSelector];
        (bool isSource, bool isDestination, bool isCustom) = parseChainFlags(
            chain.flags
        );

        require(
            chain.bridgeAddressHash == _bridgeAddressRipemd160Hash &&
                (_isSource ? isSource : isDestination) &&
                isCustom == _isCustom,
            "ChainManager: invalid chain data"
        );
    }

    function parseChainFlags(
        uint8 _flags
    ) public pure returns (bool, bool, bool) {
        return (
            getFlag(_flags, 0), // isSource
            getFlag(_flags, 1), // isDestination
            getFlag(_flags, 2) // isCustom
        );
    }

    function getFlag(
        uint8 _flags,
        uint8 _position
    ) private pure returns (bool) {
        return (_flags & (1 << _position)) != 0;
    }
}
