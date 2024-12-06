// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRouterClient} from "./CCIP/IRouterClient.sol";
import {Client} from "./CCIP/Client.sol";
import {CCIPReceiver} from "./CCIP/CCIPReceiver.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {Pausable} from "./Pausable.sol";
import {RandomBytes32Generator} from "./RandomBytes32Generator.sol";
import {UniqueRequestIdGuard} from "./UniqueRequestIdGuard.sol";

contract FeyorraBridge is
    CCIPReceiver,
    Pausable,
    RandomBytes32Generator,
    UniqueRequestIdGuard
{
    using SafeERC20 for IERC20;

    struct TokenAmount {
        address recipient;
        uint256 amount;
    }

    struct CustomChain {
        uint256 fees;
        bool isCustom;
    }

    address public immutable feyToken;

    mapping(uint64 => CustomChain) public customChains;

    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(uint64 => bool) public allowlistedSourceChains;
    mapping(address => bool) public allowlistedSenders;

    event TransferFeyorraRequest(
        bytes32 indexed requestId,
        uint64 indexed destinationChainSelector,
        address indexed spender,
        bytes receiverBridge,
        uint256 amount,
        bytes recipient,
        uint256 fees
    );

    event ExecuteBridgeTransfer(
        bytes32 indexed requestId,
        uint64 indexed sourceChainSelector,
        address indexed recipient,
        uint256 amount,
        bytes senderBridge
    );

    event RefundExcessFee(address indexed recipient, uint256 amount);

    error NotEnoughFees(uint256 feesSent, uint256 requiredFees);
    error NothingToWithdraw();
    error DestinationChainNotAllowlisted(uint64 destinationChainSelector);
    error SourceChainNotAllowlisted(uint64 sourceChainSelector);
    error SenderNotAllowlisted(address sender);
    error InvalidReceiverAddress();
    error CustomChainSelectorError(uint64 chainSelector);

    constructor(address _router, address _feyToken) CCIPReceiver(_router) {
        feyToken = _feyToken;
    }

    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        if (!allowlistedDestinationChains[_destinationChainSelector])
            revert DestinationChainNotAllowlisted(_destinationChainSelector);
        _;
    }

    modifier onlyAllowlistedSource(
        uint64 _sourceChainSelector,
        address _sender
    ) {
        if (!allowlistedSourceChains[_sourceChainSelector])
            revert SourceChainNotAllowlisted(_sourceChainSelector);
        if (!allowlistedSenders[_sender]) revert SenderNotAllowlisted(_sender);
        _;
    }

    modifier validateReceiver(address _receiver) {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        _;
    }

    modifier checkCustomChainSelector(uint64 _chainSelector, bool _isCustom) {
        if (customChains[_chainSelector].isCustom != _isCustom)
            revert CustomChainSelectorError(_chainSelector);
        _;
    }

    function updateCustomChain(
        uint64 _chainSelector,
        uint256 _fees,
        bool _isCustom
    ) external onlyOwner {
        customChains[_chainSelector] = CustomChain({
            fees: _fees,
            isCustom: _isCustom
        });
    }

    function allowlistDestinationChain(
        uint64 _destinationChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    function allowlistSourceChain(
        uint64 _sourceChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
    }

    function allowlistSender(address _sender, bool allowed) external onlyOwner {
        allowlistedSenders[_sender] = allowed;
    }

    function estimateFee(
        uint64 _destinationChainSelector,
        address _receiverBridge,
        uint256 _amount,
        address _recipient,
        bytes memory _ccipExtraArgs
    ) external view returns (uint256) {
        Client.EVM2AnyMessage memory evm2AnyMessage = buildCCIPMessage(
            _receiverBridge,
            TokenAmount({amount: _amount, recipient: _recipient}),
            address(0x0),
            _ccipExtraArgs
        );

        IRouterClient router = IRouterClient(getRouter());

        return router.getFee(_destinationChainSelector, evm2AnyMessage);
    }

    function transferFeyorraRequest(
        uint64 _destinationChainSelector,
        address _receiverBridge,
        uint256 _amount,
        address _recipient,
        bytes memory _ccipExtraArgs
    )
        external
        payable
        whenNotPaused
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        validateReceiver(_receiverBridge)
        checkCustomChainSelector(_destinationChainSelector, false)
        returns (bytes32 requestId)
    {
        Client.EVM2AnyMessage memory evm2AnyMessage = buildCCIPMessage(
            _receiverBridge,
            TokenAmount({amount: _amount, recipient: _recipient}),
            address(0),
            _ccipExtraArgs
        );

        IRouterClient router = IRouterClient(getRouter());

        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (fees > msg.value) {
            revert NotEnoughFees(msg.value, fees);
        }

        IERC20(feyToken).safeTransferFrom(msg.sender, address(this), _amount);

        requestId = router.ccipSend{value: fees}(
            _destinationChainSelector,
            evm2AnyMessage
        );

        emit TransferFeyorraRequest(
            requestId,
            _destinationChainSelector,
            msg.sender,
            abi.encodePacked(_receiverBridge),
            _amount,
            abi.encodePacked(_recipient),
            fees
        );

        excessIfNeeded(fees);
    }

    function transferFeyorraRequest(
        uint64 _destinationChainSelector,
        bytes calldata _receiverBridge,
        uint256 _amount,
        bytes calldata _recipient
    )
        external
        payable
        whenNotPaused
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        checkCustomChainSelector(_destinationChainSelector, true)
        returns (bytes32 requestId)
    {
        require(_receiverBridge.length > 0, "Invalid receiver bridge");

        uint256 fees = customChains[_destinationChainSelector].fees;

        if (fees > msg.value) {
            revert NotEnoughFees(msg.value, fees);
        }

        IERC20(feyToken).safeTransferFrom(msg.sender, address(this), _amount);
        requestId = generateRandomBytes32();

        emit TransferFeyorraRequest(
            requestId,
            _destinationChainSelector,
            msg.sender,
            _receiverBridge,
            _amount,
            _recipient,
            fees
        );

        excessIfNeeded(fees);
    }

    function excessIfNeeded(uint256 fees) private {
        if (msg.value > fees) {
            uint256 refundAmount = msg.value - fees;

            (bool isRefundSuccess, ) = payable(msg.sender).call{
                value: refundAmount
            }("");
            if (isRefundSuccess) {
                emit RefundExcessFee(msg.sender, refundAmount);
            }
        }
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory _any2EvmMessage
    )
        internal
        override
        whenNotPaused
        onlyAllowlistedSource(
            _any2EvmMessage.sourceChainSelector,
            abi.decode(_any2EvmMessage.sender, (address))
        )
    {
        executeBridgeTransfer(
            _any2EvmMessage.messageId,
            _any2EvmMessage.sourceChainSelector,
            _any2EvmMessage.sender,
            abi.decode(_any2EvmMessage.data, (TokenAmount))
        );
    }

    function manualExecuteBridgeTransfer(
        bytes32 _requestId,
        uint64 _sourceChainSelector,
        bytes calldata _senderBridge,
        uint256 _amount,
        address _recipient
    )
        external
        whenNotPaused
        onlyOwner
        onlyNotProcessedRequestId(_requestId)
        checkCustomChainSelector(_sourceChainSelector, true)
    {
        executeBridgeTransfer(
            _requestId,
            _sourceChainSelector,
            _senderBridge,
            TokenAmount(_recipient, _amount)
        );
    }

    function executeBridgeTransfer(
        bytes32 _requestId,
        uint64 _sourceChainSelector,
        bytes memory _senderBridge,
        TokenAmount memory _tokenAmount
    ) private {
        IERC20(feyToken).safeTransfer(
            _tokenAmount.recipient,
            _tokenAmount.amount
        );

        emit ExecuteBridgeTransfer(
            _requestId,
            _sourceChainSelector,
            _tokenAmount.recipient,
            _tokenAmount.amount,
            _senderBridge
        );
    }

    function buildCCIPMessage(
        address _receiverBridge,
        TokenAmount memory _tokenAmount,
        address _feeTokenAddress,
        bytes memory _ccipExtraArgs
    ) private pure returns (Client.EVM2AnyMessage memory) {
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiverBridge),
                data: abi.encode(_tokenAmount),
                tokenAmounts: new Client.EVMTokenAmount[](0),
                extraArgs: _ccipExtraArgs,
                feeToken: _feeTokenAddress
            });
    }

    function withdrawToken(address _beneficiary) public onlyOwner {
        uint256 amount = IERC20(feyToken).balanceOf(address(this));

        if (amount == 0) {
            revert NothingToWithdraw();
        }

        IERC20(feyToken).safeTransfer(_beneficiary, amount);
    }

    function withdrawNative(address _beneficiary) public onlyOwner {
        uint256 amount = address(this).balance;

        if (amount == 0) {
            revert NothingToWithdraw();
        }

        (bool success, ) = payable(_beneficiary).call{value: amount}("");
        require(success, "Transfer failed");
    }
}
