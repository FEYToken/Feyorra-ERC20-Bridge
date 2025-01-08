// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRouterClient} from "./CCIP/IRouterClient.sol";
import {Client} from "./CCIP/Client.sol";
import {CCIPReceiver} from "./CCIP/CCIPReceiver.sol";
import {SafeERC20} from "./ERC20/SafeERC20.sol";
import {IERC20} from "./ERC20/IERC20.sol";
import {IBurnable} from "./ERC20/IBurnable.sol";
import {IMintable} from "./ERC20/IMintable.sol";
import {OwnableWithTimeLockRole} from "./Access/OwnableWithTimeLockRole.sol";
import {Pausable} from "./Access/Pausable.sol";
import {SingleTokenInOutRateLimiter} from "./RateLimit/SingleTokenInOutRateLimiter.sol";
import {RateLimiter} from "./RateLimit/RateLimiter.sol";
import {RequestIdGenerator} from "./RequestIdGenerator.sol";
import {UniqueRequestIdGuard} from "./UniqueRequestIdGuard.sol";
import {ChainManager} from "./ChainManager.sol";

contract FeyorraBridge is
    CCIPReceiver,
    Pausable,
    RequestIdGenerator,
    UniqueRequestIdGuard,
    SingleTokenInOutRateLimiter,
    ChainManager
{
    using SafeERC20 for IERC20;

    struct TokenAmount {
        address recipient;
        uint256 amount;
    }

    bool public immutable isOriginalChain;
    address public immutable feyToken;

    event TransferFeyorraRequest(
        bytes32 indexed requestId,
        uint64 indexed destinationChainSelector,
        address indexed spender,
        address receiverBridge,
        uint256 amount,
        address recipient,
        uint256 fees
    );

    event CustomTransferFeyorraRequest(
        bytes32 indexed requestId,
        uint64 indexed destinationChainSelector,
        address indexed spender,
        bytes receiverBridge,
        uint256 amount,
        bytes recipient,
        uint88 fees,
        uint256 nonce
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

    constructor(
        address _router,
        address _feyToken,
        bool _isOriginalChain,
        RateLimiter.InitBucket[2] memory _tokenTransferLimitConfig,
        address _immediateOwner,
        address _timeLockedOwner
    )
        OwnableWithTimeLockRole(_immediateOwner, _timeLockedOwner)
        CCIPReceiver(_router)
        SingleTokenInOutRateLimiter(
            _feyToken,
            _tokenTransferLimitConfig[0],
            _tokenTransferLimitConfig[1]
        )
    {
        isOriginalChain = _isOriginalChain;
        feyToken = _feyToken;
    }

    function setRouter(address _router) external onlyOwner(true) {
        _setRouter(_router);
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
    ) external payable whenNotPaused returns (bytes32 requestId) {
        require(
            _recipient != address(0x0) && _amount > 0,
            "Invalid recipient or amount"
        );

        validateChain(
            _destinationChainSelector,
            ripemd160(abi.encode(_receiverBridge)),
            false,
            false
        );
        enforceTokenTransferLimit(true, _amount);

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

        processIncomingTokens(msg.sender, _amount);

        requestId = router.ccipSend{value: fees}(
            _destinationChainSelector,
            evm2AnyMessage
        );

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

    function processIncomingTokens(address _spender, uint256 _amount) private {
        IERC20(feyToken).safeTransferFrom(_spender, address(this), _amount);

        if (!isOriginalChain) {
            IBurnable(feyToken).burn(_amount);
        }
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

    function transferFeyorraRequest(
        uint64 _destinationChainSelector,
        bytes calldata _receiverBridge,
        uint256 _amount,
        bytes calldata _recipient
    ) external payable whenNotPaused returns (bytes32) {
        require(
            _recipient.length > 0 && _amount > 0,
            "Invalid recipient or amount"
        );

        validateChain(
            _destinationChainSelector,
            ripemd160(_receiverBridge),
            false,
            true
        );
        enforceTokenTransferLimit(true, _amount);

        uint88 fees = chains[_destinationChainSelector].fees;
        if (fees > msg.value) {
            revert NotEnoughFees(msg.value, fees);
        }

        processIncomingTokens(msg.sender, _amount);

        (bytes32 requestId, uint256 nonce) = getRequestId(
            _destinationChainSelector,
            _amount,
            _receiverBridge,
            _recipient
        );

        emit CustomTransferFeyorraRequest(
            requestId,
            _destinationChainSelector,
            msg.sender,
            _receiverBridge,
            _amount,
            _recipient,
            fees,
            nonce
        );

        excessIfNeeded(fees);

        return requestId;
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory _any2EvmMessage
    ) internal override whenNotPaused {
        validateChain(
            _any2EvmMessage.sourceChainSelector,
            ripemd160(_any2EvmMessage.sender),
            true,
            false
        );

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
        onlyOwner(false)
        onlyNotProcessedRequestId(_requestId)
    {
        validateChain(
            _sourceChainSelector,
            ripemd160(_senderBridge),
            true,
            true
        );

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
        enforceTokenTransferLimit(false, _tokenAmount.amount);

        if (!isOriginalChain) {
            IMintable(feyToken).mint(_tokenAmount.amount);
        }

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

    function updateTokenTransferLimitConfig(
        bool _isInput,
        uint128 _tokenTransferCapacity,
        uint128 _tokenTransferRate,
        bool _isDisabled
    ) public onlyOwner(true) {
        _updateTokenTransferLimitConfig(
            feyToken,
            _isInput,
            _tokenTransferCapacity,
            _tokenTransferRate,
            _isDisabled
        );
    }

    function withdrawToken(address _beneficiary) public onlyOwner(true) {
        uint256 amount = IERC20(feyToken).balanceOf(address(this));

        if (amount == 0) {
            revert NothingToWithdraw();
        }

        IERC20(feyToken).safeTransfer(_beneficiary, amount);
    }

    function withdrawNative(address _beneficiary) public onlyOwner(true) {
        uint256 amount = address(this).balance;

        if (amount == 0) {
            revert NothingToWithdraw();
        }

        (bool success, ) = payable(_beneficiary).call{value: amount}("");
        require(success, "Transfer failed");
    }
}
