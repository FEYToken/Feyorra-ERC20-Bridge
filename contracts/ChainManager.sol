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

    struct ChainView {
        uint64 chainSelector;
        bytes bridgeAddress;
        uint88 fees;
        bool isSource;
        bool isDestination;
        bool isCustom;
    }

    bool private initialized;
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

    event ChainFeesUpdated(
        uint64 indexed chainSelector,
        bytes bridgeAddress,
        uint88 fees
    );

    function setupChains(
        ChainView[] calldata _chains
    ) external onlyOwner(false) {
        require(!initialized, "ChainManager: already initialized");
        initialized = true;

        for (uint256 i = 0; i < _chains.length; i++) {
            _updateChain(_chains[i]);
        }
    }

    function deleteChain(
        uint64 _chainSelector
    ) external whenNotPaused onlyOwner(true) {
        delete chains[_chainSelector];
        emit ChainDeleted(_chainSelector);
    }

    function updateChain(
        ChainView calldata _chain
    ) external whenNotPaused onlyOwner(true) {
        _updateChain(_chain);
    }

    function _updateChain(ChainView calldata _chain) private {
        require(
            _chain.bridgeAddress.length > 0,
            "ChainManager: invalid bridge address"
        );

        if (_chain.isCustom) {
            require(
                _chain.fees > 0,
                "ChainManager: invalid fees for custom chain"
            );
        }

        uint8 flags = 0;

        flags = setFlag(flags, 0, _chain.isSource);
        flags = setFlag(flags, 1, _chain.isDestination);
        flags = setFlag(flags, 2, _chain.isCustom);

        chains[_chain.chainSelector] = Chain({
            bridgeAddressHash: ripemd160(_chain.bridgeAddress),
            fees: _chain.fees,
            flags: flags
        });

        emit ChainUpdated({
            chainSelector: _chain.chainSelector,
            bridgeAddress: _chain.bridgeAddress,
            fees: _chain.fees,
            isSource: _chain.isSource,
            isDestination: _chain.isDestination,
            isCustom: _chain.isCustom
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

    function updateChainFees(
        uint64 _chainSelector,
        bytes calldata _bridgeAddress,
        uint88 _fees
    ) external whenNotPaused onlyOwner(false) {
        require(
            _fees > 0 && _bridgeAddress.length > 0,
            "ChainManager: invalid fees or bridge address"
        );

        Chain storage chain = chains[_chainSelector];
        require(
            chain.bridgeAddressHash == ripemd160(_bridgeAddress),
            "ChainManager: invalid bridge address"
        );

        chain.fees = _fees;

        emit ChainFeesUpdated(_chainSelector, _bridgeAddress, _fees);
    }
}
