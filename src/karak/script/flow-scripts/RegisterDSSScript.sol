// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

// this is a test for the event "Core:DSSRegistered"
import "forge-std/Script.sol";
import {console2} from "forge-std/Script.sol";
import {Core} from "../../src/Core.sol";
import {MockDSS} from "./MockDSS.sol";

contract RegisterDSSScript is Script {
    address private constant CORE_ADDRESS = 0x61c36a8d610163660E21a8b7359e1Cac0C9133e1;
    uint256 private constant MAX_SLASHABLE_PERCENTAGE_WAD = 100000000000000000;

    function run() external {
        vm.startBroadcast();

        Core core = Core(CORE_ADDRESS);

        MockDSS mockDSS = new MockDSS();
        address DSS_ADDRESS = address(mockDSS);

        console2.log("Deploying and Registering DSS...");
        console2.log("DSS Address:", DSS_ADDRESS);
        console2.log("Max Slashable Percentage (WAD):", MAX_SLASHABLE_PERCENTAGE_WAD);

        mockDSS.registerSelf(core, MAX_SLASHABLE_PERCENTAGE_WAD);

        console2.log("DSS Registration completed");

        vm.stopBroadcast();
    }
}
