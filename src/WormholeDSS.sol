// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {IDSS} from "./karak/src/interfaces/IDSS.sol";
import {ICore} from "./karak/src/interfaces/ICore.sol";
import {Operator} from "./karak/src/entities/Operator.sol";
import {BN254} from "./karak-onchain-sdk/entities/Bn254.sol";
import "./libraries/Transceiver.sol";
import "wormhole-solidity-sdk/Utils.sol";
import "./interfaces/IWormholeDSSReceiver.sol";
import "./libraries/PausableOwnable.sol";
import {BlsBaseDSS} from "./karak-onchain-sdk/BlsBaseDSS.sol";
import {BlsBaseDSSLib} from "./karak-onchain-sdk/entities/BlsBaseDSSLib.sol";
import {IStakeViewer} from "./karak-onchain-sdk/interfaces/IStakeViewer.sol";

contract WormholeDSS is PausableOwnable, BlsBaseDSS {
    using BN254 for BN254.G1Point;
    using BlsBaseDSSLib for BlsBaseDSSLib.State;

    /* ======= State Variables ======= */

    mapping(uint16 chainId => uint256 price) chainIdPrice;
    IStakeViewer stakeViewer;

    constructor() BlsBaseDSS() {
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

    function initialize(address _core, IStakeViewer _stakeViewer, uint256 maxSlashablePercentageWad, uint8 thresholdPercentage) external initializer {
        __PausedOwnable_init(msg.sender, msg.sender);
        init(_core, maxSlashablePercentageWad, thresholdPercentage, REGISTRATION_MESSAGE_HASH);
        stakeViewer = _stakeViewer;
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
        if (deliveryPayment > chainIdPrice[sourceChain]) {
            address refundTo = address(uint160(uint256(refundAddress)));
            uint256 refundAmount = deliveryPayment - chainIdPrice[sourceChain];

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
        address[] memory nonSigningOperators,
        BN254.G2Point memory aggG2Pubkey,
        BN254.G1Point memory aggSign
    ) public view {
        if (!isThresholdReached(stakeViewer, blsBaseDssStatePtr().getOperators(), nonSigningOperators)) revert ThresholdNotReached();

        BN254.G1Point memory nonSigningAggG1Key = BN254.G1Point(0, 0);
        for (uint256 i = 0; i < nonSigningOperators.length; i++) {
            BN254.G1Point memory operatorG1Pubkey = BN254.G1Point(blsBaseDssStatePtr().operatorG1Pubkey[nonSigningOperators[i]].X, blsBaseDssStatePtr().operatorG1Pubkey[nonSigningOperators[i]].Y);
            nonSigningAggG1Key = nonSigningAggG1Key.plus(operatorG1Pubkey);
        }
        nonSigningAggG1Key = nonSigningAggG1Key.negate();

        BN254.G1Point memory aggregatedG1Pubkey = BN254.G1Point(blsBaseDssStatePtr().aggregatedG1Pubkey.X, blsBaseDssStatePtr().aggregatedG1Pubkey.Y);
        //calculated G1 pubkey
        BN254.G1Point memory calculatedG1Pubkey = aggregatedG1Pubkey.plus(nonSigningAggG1Key);

        BlsBaseDSSLib.verifySignature(calculatedG1Pubkey, aggG2Pubkey, aggSign, msgToHash(payload));
    }

    function msgToHash(bytes memory payload) public pure returns (bytes32) {
        return keccak256(payload);
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
    error NotCore();
    error NotOwner();
    error SenderNotOperator();
    error InsufficientPayment();
    error ThresholdNotReached();
}
