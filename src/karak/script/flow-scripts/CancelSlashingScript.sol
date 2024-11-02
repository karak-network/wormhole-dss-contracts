// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {console2} from "forge-std/Script.sol";
import {Core} from "../../src/Core.sol";
import {IDSS} from "../../src/interfaces/IDSS.sol";
import {SlasherLib} from "../../src/interfaces/ICore.sol";
import {Constants} from "../../src/interfaces/Constants.sol";

//tracks "Core:RequestedSlashing"
contract CancelSlashingScript is Script {
    address private constant CORE_ADDRESS = 0x9bd03768a7DCc129555dE410FF8E85528A4F88b5;
    address private constant OPERATOR_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address private constant DSS_ADDRESS = 0x3Aa5ebB10DC797CAC828524e59A333d0A371443c;
    address private constant VETO_COMMITTEE_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function run() external {
        Core core = Core(CORE_ADDRESS);

        console2.log("Script starting...");
        console2.log("Core address:", address(core));
        console2.log("Operator address:", OPERATOR_ADDRESS);
        console2.log("DSS address:", DSS_ADDRESS);
        console2.log("Veto Committee address:", VETO_COMMITTEE_ADDRESS);

        SlasherLib.QueuedSlashing memory queuedSlashing = SlasherLib.QueuedSlashing({
            dss: IDSS(DSS_ADDRESS),
            operator: OPERATOR_ADDRESS,
            timestamp: 1726574791, // Replace
            nonce: 4, // Replace
            vaults: new address[](1),
            slashPercentagesWad: new uint96[](1)
        });

        // Hardcoded, so need to replace after running requestSlashing.
        queuedSlashing.vaults[0] = 0xb524F3015511dC69cd2c97F0318d33ed1cB25029;
        queuedSlashing.slashPercentagesWad[0] = 99;

        require(block.timestamp <= queuedSlashing.timestamp + Constants.SLASHING_VETO_WINDOW, "Veto window has passed");

        console2.log("Cancelling slashing...");
        vm.broadcast(VETO_COMMITTEE_ADDRESS);
        try core.cancelSlashing(queuedSlashing) {
            console2.log("Slashing cancelled successfully");
        } catch Error(string memory reason) {
            console2.log("Slashing cancellation failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console2.log("Slashing cancellation failed with low-level error:");
            console2.logBytes(lowLevelData);
        }
        console2.log("Script completed.");
    }
}
