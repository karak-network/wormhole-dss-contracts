// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BN254} from "../libraries/BN254.sol";
import {IStakeViewer} from "./IStakeViewer.sol";

interface IWormholeDSS {
    function initialize(address _core, IStakeViewer _stakeViewer, uint256 maxSlashablePercentageWad) external;
    function slashOperator(address operator, uint256 index) external;
    function setChainIdPrice(uint16 chainId, uint256 price) external;
    function sendMessage(
        uint16 sourceChain,
        uint16 recipientChain,
        uint256 deliveryPayment,
        address caller,
        bytes32 sourceNttManagerAddress,
        bytes32 recipientNttManagerAddress,
        bytes32 refundAddress,
        bytes memory nttManagerMessage
    ) external payable;
    function operatorSignaturesValid(
        bytes memory payload,
        address[] calldata nonSigningOperators,
        BN254.G2Point calldata aggG2Pubkey,
        BN254.G1Point calldata aggSign
    ) external view;
    function msgToHash(bytes memory payload) external pure returns (bytes32);
    function deliveryPrice(uint16 chainId) external view returns (uint256);

    error NotCore();
    error NotOwner();
    error SenderNotOperator();
    error InsufficientPayment();
    error ThresholdNotReached();
}