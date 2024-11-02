// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {console2} from "forge-std/Script.sol";
import {Core} from "../../src/Core.sol";
import {IDSS} from "../../src/interfaces/IDSS.sol";
import {SlasherLib} from "../../src/interfaces/ICore.sol";

//tracks "CancelledSlashing"
contract RequestSlashingScript is Script {
    address private constant CORE_ADDRESS = 0x61c36a8d610163660E21a8b7359e1Cac0C9133e1;
    address private constant OPERATOR_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address private constant VAULT_ADDRESS = 0xb524F3015511dC69cd2c97F0318d33ed1cB25029;
    address private constant DSS_ADDRESS = 0x3Aa5ebB10DC797CAC828524e59A333d0A371443c;

    function run() external {
        Core core = Core(CORE_ADDRESS);
        IDSS dss = IDSS(DSS_ADDRESS);

        console2.log("Script starting...");
        console2.log("Core address:", address(core));
        console2.log("Operator address:", OPERATOR_ADDRESS);
        console2.log("DSS address:", DSS_ADDRESS);
        console2.log("Vault address:", VAULT_ADDRESS);

        require(core.isDSSRegistered(dss), "DSS is not registered");
        require(core.isOperatorRegisteredToDSS(OPERATOR_ADDRESS, dss), "Operator is not registered to DSS");

        SlasherLib.SlashRequest memory slashRequest = SlasherLib.SlashRequest({
            operator: OPERATOR_ADDRESS,
            slashPercentagesWad: new uint96[](1),
            vaults: new address[](1)
        });
        slashRequest.slashPercentagesWad[0] = 1e16; // 1%
        slashRequest.vaults[0] = VAULT_ADDRESS;

        console2.log("Requesting slashing...");

        vm.broadcast(DSS_ADDRESS);
        try core.requestSlashing(slashRequest) returns (SlasherLib.QueuedSlashing memory queuedSlashing) {
            console2.log("Slashing requested successfully");
            console2.log("Queued Slashing details:");
            console2.log("  DSS:", address(queuedSlashing.dss));
            console2.log("  Timestamp:", queuedSlashing.timestamp);
            console2.log("  Operator:", queuedSlashing.operator);
            console2.log("  Nonce:", queuedSlashing.nonce);
            for (uint256 i = 0; i < queuedSlashing.vaults.length; i++) {
                console2.log("  Vault:", queuedSlashing.vaults[i]);
                console2.log("  Slash Percentages:", queuedSlashing.slashPercentagesWad[i]);
            }
        } catch Error(string memory reason) {
            console2.log("Slashing request failed with reason:", reason);
        }
        console2.log("Script completed.");
    }
}
