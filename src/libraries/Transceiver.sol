// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import "wormhole-solidity-sdk/Utils.sol";

import "./TransceiverStructs.sol";
import "./PausableOwnable.sol";
import "@openzeppelin-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./Implementation.sol";

import "../interfaces/INttManager.sol";
import "../interfaces/ITransceiver.sol";
import "../interfaces/IOwnableUpgradeable.sol";

/// @title Transceiver
/// @author Wormhole Project Contributors.
/// @notice This contract is a base contract for Transceivers.
/// @dev The Transceiver provides basic functionality for transmitting / receiving NTT messages.
///      The contract supports pausing via an admin or owner and is upgradable.
///
/// @dev The interface for receiving messages is not enforced by this contract.
///      Instead, inheriting contracts should implement their own receiving logic,
///      based on the verification model and serde logic associated with message handling.
abstract contract Transceiver is ITransceiver, PausableOwnable, ReentrancyGuardUpgradeable {
    /// @dev updating bridgeNttManager requires a new Transceiver deployment.
    /// Projects should implement their own governance to remove the old Transceiver
    /// contract address and then add the new one.
    address public nttManager;
    address public nttManagerToken;
    address deployer;
    mapping(bytes payload => bool consumed) public consumedMessages;

    event MessageAlreadyConsumed(bytes payload);

    /// =============== MODIFIERS ===============================================

    modifier onlyNttManager() {
        if (msg.sender != nttManager) {
            revert CallerNotNttManager(msg.sender);
        }
        _;
    }

    /// =============== ADMIN ===============================================

    function _initialize(address _nttManager) internal {
        nttManager = _nttManager;
        nttManagerToken = INttManager(nttManager).token();
        deployer = msg.sender;

        __ReentrancyGuard_init();
        // owner of the transceiver is set to the owner of the nttManager
        __PausedOwnable_init(msg.sender, getNttManagerOwner());
    }

    /// @dev transfer the ownership of the transceiver to a new address
    /// the nttManager should be able to update transceiver ownership.
    function transferTransceiverOwnership(address newOwner) external onlyNttManager {
        _transferOwnership(newOwner);
    }

    /// =============== GETTERS & SETTERS ===============================================

    function getNttManagerOwner() public view returns (address) {
        return IOwnableUpgradeable(nttManager).owner();
    }

    function getNttManagerToken() public view virtual returns (address) {
        return nttManagerToken;
    }

    function getTransceiverType() external view virtual returns (string memory);

    /// =============== TRANSCEIVING LOGIC ===============================================

    /// @inheritdoc ITransceiver
    function quoteDeliveryPrice(uint16 targetChain, TransceiverStructs.TransceiverInstruction memory instruction)
        external
        view
        returns (uint256)
    {
        return _quoteDeliveryPrice(targetChain, instruction);
    }

    /// @inheritdoc ITransceiver
    function sendMessage(
        uint16 recipientChain,
        TransceiverStructs.TransceiverInstruction memory instruction,
        bytes memory nttManagerMessage,
        bytes32 recipientNttManagerAddress,
        bytes32 refundAddress
    ) external payable nonReentrant onlyNttManager {
        _sendMessage(
            recipientChain,
            msg.value,
            msg.sender,
            recipientNttManagerAddress,
            refundAddress,
            instruction,
            nttManagerMessage
        );
    }

    /// ============================= INTERNAL =========================================

    function _sendMessage(
        uint16 recipientChain,
        uint256 deliveryPayment,
        address caller,
        bytes32 recipientNttManagerAddress,
        bytes32 refundAddress,
        TransceiverStructs.TransceiverInstruction memory transceiverInstruction,
        bytes memory nttManagerMessage
    ) internal virtual;

    // @define This method is called by the BridgeNttManager contract to send a cross-chain message.
    // @reverts if:
    //     - `recipientNttManagerAddress` does not match the address of this manager contract
    function _deliverToNttManager(
        uint16 sourceChainId,
        bytes32 sourceNttManagerAddress,
        bytes32 recipientNttManagerAddress,
        TransceiverStructs.NttManagerMessage memory payload
    ) internal virtual {
        if (recipientNttManagerAddress != toUniversalAddress(nttManager)) {
            revert UnexpectedRecipientNttManagerAddress(toUniversalAddress(nttManager), recipientNttManagerAddress);
        }
        if (consumedMessages[payload.payload]) {
            emit MessageAlreadyConsumed(payload.payload);
            return;
        }
        consumedMessages[payload.payload] = true;
        INttManager(nttManager).attestationReceived(sourceChainId, sourceNttManagerAddress, payload);
    }

    function _quoteDeliveryPrice(
        uint16 targetChain,
        TransceiverStructs.TransceiverInstruction memory transceiverInstruction
    ) internal view virtual returns (uint256);
}
