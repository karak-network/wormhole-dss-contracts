// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

// this test is to check for "Core:UnregisterOperatorToDSS"
import "forge-std/Script.sol";
import {console2} from "forge-std/Script.sol";
import {Core} from "../../src/Core.sol";
import {IDSS} from "../../src/interfaces/IDSS.sol";
import {MockDSS} from "../../test/helpers/contracts/MockDSS.sol";
import {Operator} from "../../src/entities/Operator.sol";
import {Constants} from "../../src/interfaces/Constants.sol";

contract UnregisterOperatorFromDSSScript is Script {
    address private constant CORE_ADDRESS = 0x9bd03768a7DCc129555dE410FF8E85528A4F88b5;
    address private constant OPERATOR_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address private constant DSS_ADDRESS = 0x322813Fd9A801c5507c9de605d63CEA4f2CE6c44;

    function run() external {
        Core core = Core(CORE_ADDRESS);

        console2.log("Script starting...");
        console2.log("Core address:", address(core));
        console2.log("Operator address:", OPERATOR_ADDRESS);

        IDSS dss = IDSS(DSS_ADDRESS);
        console2.log("DSS address:", DSS_ADDRESS);

        console2.log("Checking if Operator is registered to DSS...");
        bool isOperatorRegistered = core.isOperatorRegisteredToDSS(OPERATOR_ADDRESS, dss);
        console2.log("Is Operator registered to DSS:", isOperatorRegistered);

        if (!isOperatorRegistered) {
            console2.log("Operator is not registered to this DSS. Cannot unregister.");
            return;
        }

        console2.log("Unregistering Operator from DSS...");
        unregisterOperatorFromDSS(core, dss);

        isOperatorRegistered = core.isOperatorRegisteredToDSS(OPERATOR_ADDRESS, dss);
        console2.log("Is Operator still registered to DSS:", isOperatorRegistered);

        console2.log("Script completed.");
    }

    function unregisterOperatorFromDSS(Core core, IDSS dss) public {
        vm.startBroadcast(OPERATOR_ADDRESS);
        try core.unregisterOperatorFromDSS(dss) {
            console2.log("Operator successfully unregistered from DSS");
        } catch Error(string memory reason) {
            console2.log("Unregistration failed. Reason:", reason);
        } catch (bytes memory lowLevelData) {
            console2.log("Unregistration failed. Low-level error:");
            console2.logBytes(lowLevelData);
        }
        vm.stopBroadcast();
    }
}
