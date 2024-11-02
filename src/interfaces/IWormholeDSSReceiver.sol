pragma solidity ^0.8.20;

import "../libraries/TransceiverStructs.sol";
import {BN254} from "../libraries/BlsSdk.sol";

interface IWormholeDSSReceiver {
    function receiveWormholeDSSMessage(
        bytes memory payload,
        BN254.G1Point[] calldata nonSigningOperators,
        BN254.G2Point calldata aggG2Pubkey,
        BN254.G1Point calldata aggSign
    ) external;
}
