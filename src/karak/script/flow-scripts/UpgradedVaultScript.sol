// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Core} from "../../src/Core.sol";

contract UpgradeVaultScript is Script {
    function run() external {
        address coreAddress = 0x9bd03768a7DCc129555dE410FF8E85528A4F88b5;
        address vaultAddress = 0xb524F3015511dC69cd2c97F0318d33ed1cB25029;
        address newVaultImplAddress = 0x0000000000000000000000000000000000000001; //default impl flag
        // address newVaultImplAddress = 0x7a2088a1bFc9d81c55368AE168C2C02570cB814F;

        vm.startBroadcast();
        Core core = Core(coreAddress);
        //uncomment for non default
        // core.allowlistVaultImpl(newVaultImplAddress);
        console.log("New Vault implementation allowlisted:", newVaultImplAddress);

        //uncomment for non default
        // require(core.isVaultImplAllowListed(newVaultImplAddress), "Vault implementation not allowlisted");

        core.changeImplementationForVault(vaultAddress, newVaultImplAddress);
        console.log("Vault implementation changed. UpgradedVault event should be emitted.");

        vm.stopBroadcast();
    }
}
