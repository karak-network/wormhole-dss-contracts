// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import "./libraries/Transceiver.sol";
import "./interfaces/IWormholeDSS.sol";
import "./interfaces/IWormholeDSSReceiver.sol";
import "./interfaces/INttManager.sol";
import "./libraries/TransceiverStructs.sol";
import {BN254} from "./karak-onchain-sdk/entities/Bn254.sol";
import "wormhole-solidity-sdk/Utils.sol";

contract WormholeDSSTransceiver is Transceiver, IWormholeDSSReceiver {
    event MessageReceived(uint16 sourceChain, bytes32 sourceNttManager, bytes message);

    IWormholeDSS wormholeDSS;

    function initialize(address _nttManager, address _wormholeDssAddress) external initializer {
        super._initialize(_nttManager);
        wormholeDSS = IWormholeDSS(_wormholeDssAddress);
    }

    function getTransceiverType() external pure override returns (string memory) {
        return "WormholeDSSTransceiver";
    }

    function _sendMessage(
        uint16 recipientChain,
        uint256 deliveryPayment,
        address caller,
        bytes32 recipientNttManagerAddress,
        bytes32 refundAddress,
        TransceiverStructs.TransceiverInstruction memory transceiverInstruction,
        bytes memory nttManagerMessage
    ) internal override {
        wormholeDSS.sendMessage(
            INttManager(nttManager).chainId(),
            recipientChain,
            deliveryPayment,
            caller,
            toUniversalAddress(msg.sender),
            recipientNttManagerAddress,
            refundAddress,
            nttManagerMessage
        );
    }

    function _quoteDeliveryPrice(
        uint16 targetChain,
        TransceiverStructs.TransceiverInstruction memory transceiverInstruction
    ) internal view override returns (uint256) {
        return wormholeDSS.deliveryPrice(targetChain);
    }

    function receiveWormholeDSSMessage(
        bytes memory payload,
        address[] calldata nonSigningOperators,
        BN254.G2Point calldata aggG2Pubkey,
        BN254.G1Point calldata aggSign
    ) external whenNotPaused nonReentrant {
        (
            address sender,
            uint16 sourceChain,
            uint16 recipientChain,
            bytes32 sourceNttManager,
            bytes32 recipientNttManager,
            bytes32 refundAddress,
            bytes memory message
        ) = abi.decode(payload, (address, uint16, uint16, bytes32, bytes32, bytes32, bytes));
        if (INttManager(nttManager).chainId() != recipientChain) revert InvalidChainId();
        wormholeDSS.operatorSignaturesValid(payload, nonSigningOperators, aggG2Pubkey, aggSign);

        TransceiverStructs.NttManagerMessage memory nttMessage = TransceiverStructs.parseNttManagerMessage(message);
        _deliverToNttManager(sourceChain, sourceNttManager, recipientNttManager, nttMessage);

        emit MessageReceived(sourceChain, sourceNttManager, abi.encode(message));
    }

    modifier onlyWormmholeDSS() {
        if (msg.sender != address(wormholeDSS)) {
            revert NotWormholeDSS();
        }
        _;
    }

    error NotWormholeDSS();
    error InvalidChainId();

    receive() external payable {}
}
