// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {IDSS} from "./karak/src/interfaces/IDSS.sol";
import {ICore} from "./karak/src/interfaces/ICore.sol";
import {Operator} from "./karak/src/entities/Operator.sol";
import {BlsSdk, BN254} from "./libraries/BlsSdk.sol";
import "./libraries/Transceiver.sol";
import "wormhole-solidity-sdk/Utils.sol";
import "./interfaces/IWormholeDSSReceiver.sol";
import "./libraries/PausableOwnable.sol";

contract WormholeDSS is PausableOwnable {
    using BN254 for BN254.G1Point;

    /* ======= State Variables ======= */

    ICore core;
    BlsSdk.State blsState;
    uint256 baseDeliveryPrice = 0;
    mapping(uint16 chainId => uint256 price) chainIdPrice;

    constructor() {
        _disableInitializers();
    }

    // keccak of "Register to square number dss"
    bytes32 public constant REGISTRATION_MESSAGE_HASH =
        bytes32(0xafd770cae74215647d508372fe8c5b866178892133d2611c6ec8b4f479fa0680);

    /* ======= Events ======= */

    event WormholeDSSMessageSent(
        address caller,
        uint16 sourceChain,
        uint16 recipientChain,
        bytes32 sourceNttManager,
        bytes32 recipientNttManager,
        bytes32 refundAddress,
        bytes message
    );

    /* ======= External Functions ======= */

    function initialize(ICore _core, uint256 _baseDeliveryPrice) external initializer {
        __PausedOwnable_init(msg.sender, msg.sender);
        core = _core;
        baseDeliveryPrice = _baseDeliveryPrice;
    }

    function registerDSS(uint256 wadPercentage) external {
        core.registerDSS(wadPercentage);
    }

    // can include a condition in which operator would be kicked out as well get slashed
    function slashOperator(address operator, uint256 index) external onlyOwner {}

    function setChainIdPrice(uint16 chainId, uint256 price) external onlyOwner {
        chainIdPrice[chainId] = price;
    }

    function sendMessage(
        uint16 sourceChain,
        uint16 recipientChain,
        uint256 deliveryPayment,
        address caller,
        bytes32 sourceNttManagerAddress,
        bytes32 recipientNttManagerAddress,
        bytes32 refundAddress,
        bytes memory nttManagerMessage
    ) external payable {
        if (msg.value < deliveryPayment) revert InsufficientPayment();
        if (deliveryPayment > baseDeliveryPrice) {
            address refundTo = address(uint160(uint256(refundAddress)));
            uint256 refundAmount = deliveryPayment - baseDeliveryPrice;

            (bool success,) = refundTo.call{value: refundAmount}("");
            require(success, "Refund failed");
        }

        emit WormholeDSSMessageSent(
            caller,
            sourceChain,
            recipientChain,
            sourceNttManagerAddress,
            recipientNttManagerAddress,
            refundAddress,
            nttManagerMessage
        );
    }

    function operatorSignaturesValid(
        bytes memory payload,
        BN254.G1Point[] calldata nonSigningOperators,
        BN254.G2Point calldata aggG2Pubkey,
        BN254.G1Point calldata aggSign
    ) public view {
        // TODO: update to weighted majoirty
        if (nonSigningOperators.length > (blsState.allOperatorPubkeyG1.length / 2)) {
            revert NotEnoughOperatorsForMajority();
        }

        BN254.G1Point memory nonSigningAggG1Key = BN254.G1Point(0, 0);
        for (uint256 i = 0; i < nonSigningOperators.length; i++) {
            nonSigningAggG1Key = nonSigningAggG1Key.plus(nonSigningOperators[i]);
        }
        nonSigningAggG1Key = nonSigningAggG1Key.negate();

        //calculated G1 pubkey
        BN254.G1Point memory calculatedG1Pubkey = blsState.aggregatedG1Pubkey.plus(nonSigningAggG1Key);

        BlsSdk.verifySignature(calculatedG1Pubkey, aggG2Pubkey, aggSign, msgToHash(payload));
    }

    /* ======= Hooks ======= */

    function supportsInterface(bytes4 interfaceID) external view returns (bool) {
        if (interfaceID == IDSS.registrationHook.selector || interfaceID == IDSS.unregistrationHook.selector) {
            return true;
        }
        return false;
    }

    function registrationHook(address operator, bytes memory extraData) external senderIsOperator(operator) {
        BlsSdk.operatorRegistration(blsState, operator, extraData, REGISTRATION_MESSAGE_HASH);
    }

    function unregistrationHook(address operator, bytes memory _extraData) external senderIsOperator(operator) {
        BlsSdk.operatorUnregistration(blsState, operator);
    }

    function requestUpdateStakeHook(address operator, Operator.StakeUpdateRequest memory newStake) external {}
    function cancelUpdateStakeHook(address operator, address vault) external {}
    function finishUpdateStakeHook(address operator) external {}
    function requestSlashingHook(address operator, uint256[] memory slashingPercentagesWad) external {}
    function cancelSlashingHook(address operator) external {}
    function finishSlashingHook(address operator) external {}

    /* ======= View Functions ======= */

    function isOperatorRegistered(address operator) external view returns (bool) {
        return BlsSdk.isOperatorRegistered(blsState, operator);
    }

    function msgToHash(bytes memory payload) public pure returns (bytes32) {
        return keccak256(payload);
    }

    function allOperatorsG1() external view returns (BN254.G1Point[] memory) {
        return BlsSdk.allOperatorsG1(blsState);
    }

    function operatorG1(address operator) external view returns (BN254.G1Point memory) {
        return blsState.operatorG1Pubkey[operator];
    }

    function deliveryPrice(uint16 chainId) external view returns (uint256) {
        return chainIdPrice[chainId];
    }

    /* ======= Modifiers ======= */

    modifier senderIsOperator(address operator) {
        if (tx.origin != operator) revert SenderNotOperator();
        _;
    }

    /* ======= Errors ======= */
    error SenderNotOperator();
    error NotEnoughOperatorsForMajority();
    error NotCore();
    error InsufficientPayment();
    error NotOwner();
}
