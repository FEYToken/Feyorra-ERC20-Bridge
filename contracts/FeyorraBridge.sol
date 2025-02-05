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
import {IOwnable} from "./Access/IOwnable.sol";
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

    event WithdrawalExecuted(
        address indexed beneficiary,
        address indexed tokenAddress,
        uint256 amount
    );

    event TransferTokenOwnership(address indexed newOwner);

    error NotEnoughFees(uint256 feesSent, uint256 requiredFees);
    error ZeroTokenAddress();
    error ZeroRecipientAddress();
    error ZeroTransferAmount();
    error NothingToWithdraw();
    error NativeTransferFailed();
    error OriginalChainOwnershipTransferNotAllowed();

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
        if (_feyToken == address(0)) {
            revert ZeroTokenAddress();
        }

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

    /**
     * @notice Initiates a cross-chain transfer of FEY tokens using Chainlink CCIP.
     * @dev This function sends a request to transfer a specified amount of FEY tokens
     *      to a recipient address on a destination chain via the provided bridge address.
     *      Additional arguments can be passed for configuring CCIP-specific options.
     * @param _destinationChainSelector The identifier of the destination chain where the tokens should be transferred.
     * @param _receiverBridge The address of the bridge contract on the destination chain that will handle the transfer.
     * @param _amount The amount of FEY tokens to be transferred.
     * @param _recipient The address of the recipient on the destination chain.
     * @param _ccipExtraArgs Additional data for configuring CCIP options. One critical parameter in this field is the `gasLimit`,
     *      which determines the amount of gas allocated for executing the transaction on the destination chain.
     *      Selecting an appropriate `gasLimit` is essential to ensure the successful execution of the transaction on the
     *      target chain. An insufficient gas limit could cause the transaction to fail, resulting in the need for additional
     *      retries or manual intervention.
     *
     *      To calculate the required `gasLimit`:
     *      - Estimate the gas consumption for the destination chain transaction, taking into account the complexity of the
     *        logic executed on the destination chain (e.g., token minting, transfers, or other smart contract interactions).
     *      - Reference Chainlink's recommended practices for setting the gas limit at:
     *        https://docs.chain.link/ccip/best-practices#setting-gaslimit
     *      - Consider adding a safety margin to the estimated gas to account for variability in gas costs.
     *
     *      Ensure that the encoded `extraArgs` are properly formatted according to CCIP specifications.
     * @return requestId The unique identifier of the transfer request.
     *
     * Important notes about fee refunds:
     * - If the `msg.value` provided by the caller exceeds the required fees, the `excessIfNeeded` function attempts to
     *   refund the difference to the caller. The refund is processed using a low-level `call` to the sender's address.
     * - It is critical that the caller's address or contract can accept ETH transfers without errors.
     * - For example, contracts that lack a payable `receive` or `fallback` function, or that deliberately reject incoming
     *   ETH, will cause the refund to fail.
     * - If the refund fails, the excess ETH will not be retrievable, and the user will lose the overpaid amount. Users
     *   should ensure their address can handle ETH refunds before calling this function.
     *
     * Requirements:
     * - `_recipient` must be non-zero address.
     * - `_amount` must be greater than zero.
     * - The contract must not be paused (`whenNotPaused` modifier).
     * - The caller must send sufficient funds to cover the CCIP fee via `msg.value`.
     */
    function transferFeyorraRequest(
        uint64 _destinationChainSelector,
        address _receiverBridge,
        uint256 _amount,
        address _recipient,
        bytes memory _ccipExtraArgs
    ) external payable whenNotPaused returns (bytes32 requestId) {
        if (_recipient == address(0x0)) {
            revert ZeroRecipientAddress();
        }
        if (_amount == 0) {
            revert ZeroTransferAmount();
        }

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

    /**
     * @notice Initiates a cross-chain transfer of FEY tokens using a custom transfer mechanism.
     * @dev This function is designed for chains not supported by Chainlink CCIP, including non-EVM compatible chains.
     *      The transfer is validated against custom logic to ensure the recipient and amount are valid, and the necessary
     *      fees are provided. The request is processed by emitting an event that can be monitored for execution on the
     *      destination chain.
     * @param _destinationChainSelector The identifier of the destination chain for the token transfer.
     * @param _receiverBridge The address or identifier of the bridge contract or service on the destination chain.
     *        The format of this parameter may vary depending on the chain type (e.g., non-EVM chains).
     * @param _amount The amount of FEY tokens to transfer.
     * @param _recipient The address or identifier of the recipient on the destination chain. The format is chain-specific.
     *        For example, it could be a string, a byte array, or an address encoded as bytes.
     * @return A unique `requestId` representing the transfer request, which can be used for tracking or debugging purposes.
     *
     * Important notes about fee refunds:
     * - If the `msg.value` provided by the caller exceeds the required fees, the `excessIfNeeded` function attempts to
     *   refund the difference to the caller. The refund is processed using a low-level `call` to the sender's address.
     * - It is critical that the caller's address or contract can accept ETH transfers without errors.
     * - For example, contracts that lack a payable `receive` or `fallback` function, or that deliberately reject incoming
     *   ETH, will cause the refund to fail.
     * - If the refund fails, the excess ETH will not be retrievable, and the user will lose the overpaid amount. Users
     *   should ensure their address can handle ETH refunds before calling this function.
     *
     * Requirements:
     * - `_recipient` must be valid (non-empty).
     * - `_amount` must be greater than zero.
     * - Sufficient fees must be provided via `msg.value` to cover the transfer costs.
     * - The contract must not be paused (`whenNotPaused` modifier).
     */
    function transferFeyorraRequest(
        uint64 _destinationChainSelector,
        bytes calldata _receiverBridge,
        uint256 _amount,
        bytes calldata _recipient
    ) external payable whenNotPaused returns (bytes32) {
        if (_recipient.length == 0) {
            revert ZeroRecipientAddress();
        }
        if (_amount == 0) {
            revert ZeroTransferAmount();
        }

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
        if (_tokenAmount.recipient == address(0x0)) {
            revert ZeroRecipientAddress();
        }

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
    ) external onlyOwner(true) {
        _updateTokenTransferLimitConfig(
            feyToken,
            _isInput,
            _tokenTransferCapacity,
            _tokenTransferRate,
            _isDisabled
        );
    }

    function withdrawToken(address _beneficiary) external onlyOwner(true) {
        if (_beneficiary == address(0x0)) {
            revert ZeroRecipientAddress();
        }

        uint256 amount = IERC20(feyToken).balanceOf(address(this));
        if (amount == 0) {
            revert NothingToWithdraw();
        }

        IERC20(feyToken).safeTransfer(_beneficiary, amount);

        emit WithdrawalExecuted(_beneficiary, feyToken, amount);
    }

    function withdrawNative(address _beneficiary) external onlyOwner(true) {
        if (_beneficiary == address(0x0)) {
            revert ZeroRecipientAddress();
        }

        uint256 amount = address(this).balance;
        if (amount == 0) {
            revert NothingToWithdraw();
        }

        (bool success, ) = payable(_beneficiary).call{value: amount}("");
        if (!success) {
            revert NativeTransferFailed();
        }

        emit WithdrawalExecuted(_beneficiary, address(0x0), amount);
    }

    function transferTokenOwnership(
        address _newOwner
    ) external onlyOwner(true) {
        if (isOriginalChain) {
            revert OriginalChainOwnershipTransferNotAllowed();
        }

        IOwnable(feyToken).transferOwnership(_newOwner);
        emit TransferTokenOwnership(_newOwner);
    }
}
