// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {console2} from "forge-std/Script.sol";
import {Core} from "../../src/Core.sol";
import {IDSS} from "../../src/interfaces/IDSS.sol";
import {Operator} from "../../src/entities/Operator.sol";

//Tracks "Core:RequestedStakeUpdate"
contract RequestStakeUpdateScript is Script {
    address private constant CORE_ADDRESS = 0x61c36a8d610163660E21a8b7359e1Cac0C9133e1;
    address private constant OPERATOR_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address private constant VAULT_ADDRESS = 0xc99B9A9579e863387D1a07c3B0bdCA430B2e7d35;
    address private constant DSS_ADDRESS = 0x0B306BF915C4d645ff596e518fAf3F9669b97016;

    function run() external {
        vm.startBroadcast(OPERATOR_ADDRESS);

        Core core = Core(CORE_ADDRESS);
        IDSS dss = IDSS(DSS_ADDRESS);

        console2.log("Script starting...");
        console2.log("Core address:", address(core));
        console2.log("Operator address:", OPERATOR_ADDRESS);
        console2.log("DSS address:", DSS_ADDRESS);
        console2.log("Vault address:", VAULT_ADDRESS);

        require(core.isDSSRegistered(dss), "DSS is not registered");
        require(core.isOperatorRegisteredToDSS(OPERATOR_ADDRESS, dss), "Operator is not registered to DSS");

        console2.log("Requesting stake update...");
        Operator.StakeUpdateRequest memory request =
            Operator.StakeUpdateRequest({dss: dss, vault: VAULT_ADDRESS, toStake: true});

        try core.requestUpdateVaultStakeInDSS(request) returns (Operator.QueuedStakeUpdate memory queuedStake) {
            console2.log("Stake update requested successfully");
            console2.log("Queued Stake Update details:");
            console2.log("  Operator:", queuedStake.operator);
            console2.log("  DSS:", address(queuedStake.updateRequest.dss));
            console2.log("  Vault:", queuedStake.updateRequest.vault);
            console2.log("  To Stake:", queuedStake.updateRequest.toStake);
            console2.log("  Start Timestamp:", queuedStake.startTimestamp);
            console2.log("  Nonce:", queuedStake.nonce);
        } catch Error(string memory reason) {
            console2.log("Failed to request stake update:");
            console2.log(reason);
        } catch (bytes memory) {
            console2.log("Failed to request stake update (unknown error)");
        }

        vm.stopBroadcast();
        console2.log("Script completed.");
    }
}
