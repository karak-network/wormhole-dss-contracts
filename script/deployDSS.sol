// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {WormholeDSS} from "../src/WormholeDSS.sol";
import {ICore} from "../src/karak/src/interfaces/ICore.sol";
import "forge-std/Vm.sol";
import {IStakeViewer} from "../src/interfaces/IStakeViewer.sol";

contract DeployDSS is Script {
    address internal CORE = vm.envAddress("CORE");
    address internal STAKING_VIEWER = vm.envAddress("STAKING_VIEWER");

    function run() public {
        vm.startBroadcast();
        console2.log("Running DeployCoreLocal script. Signer:", msg.sender);
        console2.log();

        WormholeDSS dssImpl = deployDSSImplementation(CORE);
        console2.log("Address of Wormhole DSS Implementation: ", address(dssImpl));
        console2.log();

        TransparentUpgradeableProxy wormholeDSSProxy =
            new TransparentUpgradeableProxy(address(dssImpl), msg.sender, abi.encodeWithSelector(
                WormholeDSS.initialize.selector, ICore(CORE), 0
            ));
        WormholeDSS dssProxy = WormholeDSS(address(wormholeDSSProxy));

        console2.log("Address of Wormhole DSS Proxy: ", address(wormholeDSSProxy));
        console2.log();

        initializeDSS(dssProxy);

        vm.stopBroadcast();
    }

    function deployDSSImplementation(address core) public returns (WormholeDSS dss) {
        dss = new WormholeDSS();
    }

    function initializeDSS(WormholeDSS dss) public {
        dss.initialize(CORE, IStakeViewer(STAKING_VIEWER), 10e18, 30);
    }
}
