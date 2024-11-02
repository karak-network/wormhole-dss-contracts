// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {console2} from "forge-std/Script.sol";
import {Core} from "../../src/Core.sol";
import {IDSS} from "../../src/interfaces/IDSS.sol";
import {SlasherLib} from "../../src/interfaces/ICore.sol";
import {Constants} from "../../src/interfaces/Constants.sol";

//tracks "Core:FinalizedSlashing" and "Vault:Slashed"
contract FinalizeSlashingScript is Script {
    address private constant CORE_ADDRESS = 0x9bd03768a7DCc129555dE410FF8E85528A4F88b5;
    address private constant OPERATOR_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address private constant DSS_ADDRESS = 0x3Aa5ebB10DC797CAC828524e59A333d0A371443c;
    address private constant VAULT_ADDRESS = 0xb524F3015511dC69cd2c97F0318d33ed1cB25029;

    function run() external {
        Core core = Core(CORE_ADDRESS);

        console2.log("Script starting...");
        console2.log("Core address:", address(core));
        console2.log("Operator address:", OPERATOR_ADDRESS);
        console2.log("DSS address:", DSS_ADDRESS);
        console2.log("Vault address:", VAULT_ADDRESS);

        SlasherLib.QueuedSlashing memory queuedSlashing = SlasherLib.QueuedSlashing({
            dss: IDSS(DSS_ADDRESS),
            timestamp: 1723534909, //replace from slashEvents query result not logs
            operator: OPERATOR_ADDRESS,
            vaults: new address[](1),
            slashPercentagesWad: new uint96[](1),
            nonce: 2 // replace
        });
        queuedSlashing.vaults[0] = VAULT_ADDRESS;
        queuedSlashing.slashPercentagesWad[0] = uint96(30 * Constants.ONE_WAD); // confirm and replace

        console2.log("Finalizing slashing...");
        console2.log("Timestamp:", queuedSlashing.timestamp);
        console2.log("Nonce:", queuedSlashing.nonce);
        console2.log("SlashPercentage:", queuedSlashing.slashPercentagesWad[0]);

        vm.startBroadcast(DSS_ADDRESS);
        try core.finalizeSlashing(queuedSlashing) {
            console2.log("Slashing finalized successfully");
        } catch Error(string memory reason) {
            console2.log("Slashing finalization failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console2.log("Slashing finalization failed with low-level error:");
            console2.logBytes(lowLevelData);
        }
        vm.stopBroadcast();

        console2.log("Script completed.");
    }
}
