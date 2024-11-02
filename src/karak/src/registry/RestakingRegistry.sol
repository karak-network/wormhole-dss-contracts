// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";

struct KNSData {
    address entity;
    address owner;
}

struct State {
    mapping(string name => KNSData kns) resolver;
}

contract RestakingRegistry is Ownable, Initializable {
    string public constant VERSION = "1.0.0";
    // keccak256(abi.encode(uint256(keccak256("restaking-registry.state")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant STATE_SLOT = 0x9e4a6352c23084dc718b082f50a04dd356607be8eecedddafd629ee04e702100;

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) external initializer {
        _initializeOwner(owner);
    }

    function _state() internal pure returns (State storage $) {
        assembly {
            $.slot := STATE_SLOT
        }
    }

    function register(string memory kns, address entity, address owner) external {
        KNSData memory knsData = KNSData(entity, owner);

        if (knsData.owner == address(0) || knsData.entity == address(0)) revert AddressZero();

        KNSData storage currentKnsData = _state().resolver[kns];
        if (currentKnsData.entity != address(0) && currentKnsData.owner != msg.sender) revert NotKnsOwner();

        insertKns(kns, knsData);
    }

    function insertKns(string memory kns, KNSData memory knsData) internal {
        if (!validateKNSFormat(kns)) revert InvalidUrlFormat();

        _state().resolver[kns] = knsData;
        emit KnsUpdated(kns, knsData.entity, knsData.owner);
    }

    function overrideKns(string memory kns, KNSData memory knsData) external onlyOwner {
        insertKns(kns, knsData);
    }

    function validateKNSFormat(string memory input) public pure returns (bool) {
        bytes memory inputBytes = bytes(input);
        uint256[] memory dotPositions = new uint256[](5);
        uint256 dotCount = 0;

        // Find dot positions
        for (uint256 i = 0; i < inputBytes.length; i++) {
            if (inputBytes[i] == ".") {
                if (dotCount < 5) {
                    dotPositions[dotCount] = i;
                }
                dotCount++;
            }
        }

        // Ensure we have at least 4 dots
        if (dotCount < 4) {
            revert UnexpectedAmtOfDots(dotCount);
        }

        // Check the fourth segment (dss | operator | vault)
        bytes memory fourthSegment = new bytes(dotPositions[3] - dotPositions[2] - 1);
        for (uint256 i = 0; i < fourthSegment.length; i++) {
            fourthSegment[i] = inputBytes[dotPositions[2] + 1 + i];
        }

        bool validFourthSegment = keccak256(fourthSegment) == keccak256(bytes("dss"))
            || keccak256(fourthSegment) == keccak256(bytes("operator"))
            || keccak256(fourthSegment) == keccak256(bytes("vault"));

        if (!validFourthSegment) {
            revert InvalidFourthSegment(string(fourthSegment));
        }

        // Ensure all required segments are non-empty
        if (
            dotPositions[0] == 0 || dotPositions[1] == dotPositions[0] + 1 || dotPositions[2] == dotPositions[1] + 1
                || dotPositions[3] == dotPositions[2] + 1 || dotPositions[3] == inputBytes.length - 1
        ) {
            revert UnexpectedAmtOfDots(dotCount);
        }
        return true;
    }

    function getKns(string memory kns) external view returns (address entity, address owner) {
        KNSData memory knsData = _state().resolver[kns];
        return (knsData.entity, knsData.owner);
    }

    error InvalidUrlFormat();
    error NotKnsOwner();
    error AddressZero();

    // KNS validation errors
    error UnexpectedAmtOfDots(uint256 dotCount);
    error InvalidFourthSegment(string fourthSegment);

    event KnsUpdated(string kns, address entity, address owner);
}
