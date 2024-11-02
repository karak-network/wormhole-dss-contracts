// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {RestakingRegistry} from "../../src/registry/RestakingRegistry.sol";

contract TriggerKnsUpdatedScript is Script {
    function run() external {
        address registryAddress = 0x788F1E4a99fa704Edb43fAE71946cFFDDcC16ccB;

        string memory kns = "example.eth.karak.operator.io";
        address entity = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        address owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

        vm.startBroadcast();

        RestakingRegistry registry = RestakingRegistry(registryAddress);
        registry.register(kns, entity, owner);

        console.log("KNS registered:");
        console.log("KNS:", kns);
        console.logAddress(entity);
        console.logAddress(owner);

        vm.stopBroadcast();
    }
}
