// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {Core} from "../../src/Core.sol";
import {Vault} from "../../src/Vault.sol";
import {SlashingHandler} from "../../src/SlashingHandler.sol";
import {VaultLib} from "../../src/entities/VaultLib.sol";
import {IKarakBaseVault} from "../../src/interfaces/IKarakBaseVault.sol";

//test script to test "Core:DeployedVault"
contract DeployAndAllowlistScript is Script {
    function run() external {
        address coreAddress = 0x61c36a8d610163660E21a8b7359e1Cac0C9133e1;
        address slashingHandlerAddress = 0x23dB4a08f2272df049a4932a4Cc3A6Dc1002B33E;
        address vaultImplAddress = 0x0000000000000000000000000000000000000000;
        address assetAddress = 0x8A791620dd6260079BF849Dc5567aDC3F2FdC318;
        address operator = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        uint8 decimals = 6;

        vm.startBroadcast();

        Core core = Core(coreAddress);

        // Allowlist asset
        address[] memory assets = new address[](1);
        assets[0] = assetAddress;

        address[] memory slashingHandlers = new address[](1);
        slashingHandlers[0] = slashingHandlerAddress;

        core.allowlistAssets(assets, slashingHandlers);
        console.log("Asset allowlisted.");

        // uncomment for non standard impls
        // core.allowlistVaultImpl(vaultImplAddress);
        // console.log("Vault implementation allowlisted.");

        VaultLib.Config[] memory vaultConfigs = new VaultLib.Config[](1);
        vaultConfigs[0] = VaultLib.Config({
            asset: assetAddress,
            decimals: decimals,
            operator: operator,
            name: "MyVault",
            symbol: "MV",
            extraData: ""
        });

        IKarakBaseVault[] memory vaults = core.deployVaults(vaultConfigs, vaultImplAddress);
        console.log("Vault deployed.");
        console.logAddress(address(vaults[0]));

        vm.stopBroadcast();
    }
}
