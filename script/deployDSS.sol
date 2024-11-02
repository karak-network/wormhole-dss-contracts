// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Factory} from "solady/src/utils/ERC1967Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

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
import "forge-std/Vm.sol";

contract DeployDSS is Script {
    address internal NTT_MANAGER = vm.envAddress("NTT_MANAGER");
    address internal CORE = vm.envAddress("CORE");

    function run() public {
        vm.startBroadcast();
        console2.log("Running DeployCoreLocal script. Signer:", msg.sender);
        console2.log();

        WormholeDSS dssImpl = deployDSSImplementation(CORE);
        console2.log("address of Wormhole DSS Implementation: ", address(dssImpl));
        console2.log();

        TransparentUpgradeableProxy WormholeDSSproxy =
            new TransparentUpgradeableProxy(address(dssImpl), msg.sender, abi.encode(""));
        WormholeDSS dssProxy = WormholeDSS(address(WormholeDSSproxy));

        console2.log("address of Wormhole DSS Proxy: ", address(WormholeDSSproxy));
        console2.log();

        initializeDSS(dssProxy);

        vm.stopBroadcast();
    }

    function deployDSSImplementation(address core) public returns (WormholeDSS dss) {
        dss = new WormholeDSS();
    }

    function initializeDSS(WormholeDSS dss) public {
        dss.initialize(ICore(CORE), 0);
        dss.registerDSS(10e18);
    }
}
