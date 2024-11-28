// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// End consumer library.
library Client {
    /// @dev RMN depends on this struct, if changing, please notify the RMN maintainers.
    struct EVMTokenAmount {
        address token; // token address on the local chain.
        uint256 amount; // Amount of tokens.
    }

    struct Any2EVMMessage {
        bytes32 messageId; // MessageId corresponding to ccipSend on source.
        uint64 sourceChainSelector; // Source chain selector.
        bytes sender; // abi.decode(sender) if coming from an EVM chain.
        bytes data; // payload sent in original message.
        EVMTokenAmount[] destTokenAmounts; // Tokens and their amounts in their destination chain representation.
    }

    // If extraArgs is empty bytes, the default is 200k gas limit.
    struct EVM2AnyMessage {
        bytes receiver; // abi.encode(receiver address) for dest EVM chains
        bytes data; // Data payload
        EVMTokenAmount[] tokenAmounts; // Token transfers
        address feeToken; // Address of feeToken. address(0) means you will send msg.value.
        bytes extraArgs; // Populate this with _argsToBytes(EVMExtraArgsV1)
    }

    // bytes4(keccak256("CCIP EVMExtraArgsV1"));
    bytes4 public constant EVM_EXTRA_ARGS_V1_TAG = 0x97a657c9;
    struct EVMExtraArgsV1 {
        uint256 gasLimit;
    }

    function _argsToBytes(
        EVMExtraArgsV1 memory extraArgs
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(EVM_EXTRA_ARGS_V1_TAG, extraArgs);
    }
}
// "0x0000000000000000000000000000000000000000000000000000000000000000",
// ("0x0000000000000000000000000000000000000000000000000000000000000020","0x00000000000000000000000000000000000000000000000000000000000000a0","0x00000000000000000000000000000000000000000000000000000000000000e0","0x0000000000000000000000000000000000000000000000000000000000000120","0x0000000000000000000000000000000000000000000000000000000000000000","0x0000000000000000000000000000000000000000000000000000000000000140","0x0000000000000000000000000000000000000000000000000000000000000020","0x00000000000000000000000097c0b289339b61610bd000ed8d143d5b7bcd1583","0x0000000000000000000000000000000000000000000000000000000000000020","0x00000000000000000000000000000000000000000000000000000000000186a0","0x0000000000000000000000000000000000000000000000000000000000000024","0x97a657c900000000000000000000000000000000000000000000000000000000",
// "0x00030d4000000000000000000000000000000000000000000000000000000000")