// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Core} from "../../src/Core.sol";

contract UpgradeAllVaultsScript is Script {
    function run() external {
        address coreAddress = 0x9bd03768a7DCc129555dE410FF8E85528A4F88b5;
        address newVaultImplAddress = 0x59b670e9fA9D0A427751Af201D676719a970857b;

        vm.startBroadcast();

        Core core = Core(coreAddress);
        core.allowlistVaultImpl(newVaultImplAddress);
        console.log("New Vault implementation allowlisted:", newVaultImplAddress);

        require(core.isVaultImplAllowListed(newVaultImplAddress), "Vault implementation not allowlisted");

        core.changeStandardImplementation(newVaultImplAddress);
        console.log("Standard implementation changed. UpgradedAllVaults event should be emitted.");

        vm.stopBroadcast();
    }
}
