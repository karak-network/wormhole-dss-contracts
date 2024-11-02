// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {console2} from "forge-std/Script.sol";
import {Core} from "../../src/Core.sol";
import {IDSS} from "../../src/interfaces/IDSS.sol";
import {Operator} from "../../src/entities/Operator.sol";
import {Constants} from "../../src/interfaces/Constants.sol";

//Tracks "Core:FinishedStakeUpdate"
contract FinalizeStakeUpdateScript is Script {
    address private constant CORE_ADDRESS = 0x61c36a8d610163660E21a8b7359e1Cac0C9133e1;
    address private constant OPERATOR_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address private constant VAULT_ADDRESS = 0xc99B9A9579e863387D1a07c3B0bdCA430B2e7d35;
    address private constant DSS_ADDRESS = 0x0B306BF915C4d645ff596e518fAf3F9669b97016;

    function run() external {
        Core core = Core(CORE_ADDRESS);
        console2.log("Script starting...");
        console2.log("Core address:", address(core));
        console2.log("Operator address:", OPERATOR_ADDRESS);
        console2.log("DSS address:", DSS_ADDRESS);
        console2.log("Vault address:", VAULT_ADDRESS);

        //hardcoded value, change after running RequestStakeUpdateScript.
        uint48 nonce = 1;
        //hardcoded value, change after running RequestStakeUpdateScript.
        uint48 startTimestamp = 1725773619; //refer to the indexed event logs, not the script logs
        bool toStake = true;

        console2.log("Nonce:", nonce);
        console2.log("Start timestamp:", startTimestamp);
        console2.log("To Stake:", toStake);

        uint256 currentTimestamp = block.timestamp;
        console2.log("Current timestamp:", currentTimestamp);
        uint256 timePassed = currentTimestamp - startTimestamp;
        console2.log("Time passed since stake request:", timePassed);

        require(timePassed >= Constants.MIN_STAKE_UPDATE_DELAY, "Minimum delay not yet passed");

        bool isRegistered = core.isOperatorRegisteredToDSS(OPERATOR_ADDRESS, IDSS(DSS_ADDRESS));
        console2.log("Is operator registered to DSS:", isRegistered);
        require(isRegistered, "Operator not registered to DSS");
        vm.startBroadcast();

        Operator.QueuedStakeUpdate memory queuedStakeUpdate = Operator.QueuedStakeUpdate({
            nonce: nonce,
            startTimestamp: startTimestamp,
            operator: OPERATOR_ADDRESS,
            updateRequest: Operator.StakeUpdateRequest({dss: IDSS(DSS_ADDRESS), vault: VAULT_ADDRESS, toStake: toStake})
        });

        vm.stopBroadcast();

        bytes32 calculatedRoot = keccak256(abi.encode(queuedStakeUpdate));
        console2.log("Calculated root:", uint256(calculatedRoot));

        console2.log("Finalizing stake update...");

        vm.startBroadcast();
        try core.finalizeUpdateVaultStakeInDSS(queuedStakeUpdate) {
            console2.log("Stake update finalized successfully");
        } catch Error(string memory reason) {
            console2.log("Stake update finalization failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console2.log("Stake update finalization failed with low-level error:");
            console2.logBytes(lowLevelData);
        }
        vm.stopBroadcast();

        address[] memory stakedVaults = core.fetchVaultsStakedInDSS(OPERATOR_ADDRESS, IDSS(DSS_ADDRESS));
        bool vaultStaked = false;
        for (uint256 i = 0; i < stakedVaults.length; i++) {
            if (stakedVaults[i] == VAULT_ADDRESS) {
                vaultStaked = true;
                break;
            }
        }
        console2.log("Vault staked after finalization:", vaultStaked);

        console2.log("Script completed.");
    }
}
