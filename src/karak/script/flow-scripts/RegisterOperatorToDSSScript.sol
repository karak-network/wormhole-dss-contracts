// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

// this test is to check for "Core:RegisterOperatorToDSS"
import "forge-std/Script.sol";
import {console2} from "forge-std/Script.sol";
import {Core} from "../../src/Core.sol";
import {IDSS} from "../../src/interfaces/IDSS.sol";

contract RegisterOperatorToDSSScript is Script {
    address private constant CORE_ADDRESS = 0x61c36a8d610163660E21a8b7359e1Cac0C9133e1;
    address private constant DSS_ADDRESS = 0x9A9f2CCfdE556A7E9Ff0848998Aa4a0CFD8863AE;
    address private constant OPERATOR_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function run() external {
        Core core = Core(CORE_ADDRESS);

        console2.log("Script starting...");
        console2.log("Core address:", address(core));
        console2.log("DSS address:", DSS_ADDRESS);
        console2.log("Operator address:", OPERATOR_ADDRESS);

        console2.log("Checking if DSS is registered...");
        bool isDSSRegistered = core.isDSSRegistered(IDSS(DSS_ADDRESS));
        console2.log("Is DSS registered:", isDSSRegistered);

        console2.log("Checking if Operator is already registered to DSS...");
        bool isOperatorRegistered = core.isOperatorRegisteredToDSS(OPERATOR_ADDRESS, IDSS(DSS_ADDRESS));
        console2.log("Is Operator registered to DSS:", isOperatorRegistered);

        if (!isDSSRegistered) {
            console2.log("DSS is not registered. Cannot proceed with operator registration.");
            return;
        }

        if (isOperatorRegistered) {
            console2.log("Operator is already registered to this DSS.");
            return;
        }

        console2.log("Proceeding with registration...");

        vm.broadcast(OPERATOR_ADDRESS);

        console2.log("Calling registerOperatorToDSS...");
        try core.registerOperatorToDSS(IDSS(DSS_ADDRESS), "") {
            console2.log("Operator Registration to DSS completed successfully");
        } catch Error(string memory reason) {
            console2.log("Operator Registration failed. Reason:", reason);
        } catch (bytes memory lowLevelData) {
            console2.log("Operator Registration failed. Low-level error:");
            console2.logBytes(lowLevelData);
        }

        console2.log("Script completed.");
    }
}
