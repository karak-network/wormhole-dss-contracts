// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Factory} from "solady/src/utils/ERC1967Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {WormholeDSS} from "../src/WormholeDSS.sol";
import {WormholeDSSTransceiver} from "../src/WormholeDSSTransceiver.sol";

import {Core} from "../src/karak/src/Core.sol";
import {Vault} from "../src/karak/src/Vault.sol";
import {IDSS} from "../src/karak/src/interfaces/IDSS.sol";
import {ICore} from "../src/karak/src/interfaces/ICore.sol";
import {Operator} from "../src/karak/src/entities/Operator.sol";
import {VaultLib} from "../src/karak/src/entities/VaultLib.sol";
import {SlashingHandler} from "../src/karak/src/SlashingHandler.sol";
import {ERC20Mintable} from "../src/karak/test/helpers/contracts/ERC20Mintable.sol";
import {INttManager} from "../src/interfaces/INttManager.sol";
import "forge-std/Vm.sol";

contract DeployTransceiver is Script {
    address internal NTT_MANAGER = vm.envAddress("NTT_MANAGER");
    address internal WormholeDSS = vm.envAddress("WORMHOLE_DSS");

    function run() public {
        vm.startBroadcast();
        console2.log("Running DeployCoreLocal script. Signer:", msg.sender);
        console2.log();

        WormholeDSSTransceiver transceiver = deployTransceiver(address(NTT_MANAGER), WormholeDSS);
        console2.log("address of Transceiver: ", address(transceiver));
        console2.log();

        INttManager manager = INttManager(NTT_MANAGER);
        manager.setTransceiver(address(transceiver));
        manager.setThreshold(manager.getThreshold() + 1);

        vm.stopBroadcast();
    }

    function deployTransceiver(address nttManger, address dss) public returns (WormholeDSSTransceiver transceiver) {
        transceiver = new WormholeDSSTransceiver();
        transceiver.initialize(nttManger, dss);
    }
}
