// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BlsSdk, BN254} from "../libraries/BlsSdk.sol";

interface IWormholeDSS {
    function registerDSS(uint256 wadPercentage) external;
    function slashOperator(address operator, uint256 index) external;
    function sendMessage(
        uint16 sourceChain,
        uint16 recipientChain,
        uint256 deliveryPayment,
        address caller,
        bytes32 sourceNttManagerAddress,
        bytes32 recipientNttManagerAddress,
        bytes32 refundAddress,
        bytes memory nttManagerMessage
    ) external;
    function operatorSignaturesValid(
        bytes calldata payload,
        BN254.G1Point[] calldata nonSigningOperators,
        BN254.G2Point calldata aggG2Pubkey,
        BN254.G1Point calldata aggSign
    ) external;

    function isOperatorRegistered(address operator) external view returns (bool);
    function msgToHash(bytes calldata payload) external pure returns (bytes32);
    function allOperatorsG1() external view returns (BN254.G1Point[] memory);
    function deliveryPrice(uint16 chainId) external view returns (uint256);

    function operatorG1(address operator) external view returns (BN254.G1Point memory);

    error SenderNotOperator();
    error NotEnoughOperatorsForMajority();
    error NotCore();
}
