// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {DeployCoreLocal} from "./DeployCoreLocal.s.sol";
import {Core} from "../../src/Core.sol";
import {VaultLib} from "../../src/entities/VaultLib.sol";
import {RestakingRegistry} from "../../src/registry/RestakingRegistry.sol";
import {Constants} from "../../src/interfaces/Constants.sol";
import {IKarakBaseVault} from "../../src/interfaces/IKarakBaseVault.sol";

contract SetupCoreLocal is Script {
    address operator = address(this);

    function run() public {
        DeployCoreLocal dcl = new DeployCoreLocal();
        (
            address coreImpl,
            address vaultImpl,
            address slashingHandlerImpl,
            address registryImpl,
            address nativeVaultImpl,
            address nativeNodeImpl,
            address testERC20Addr,
            Core coreProxy,
            RestakingRegistry registryProxy
        ) = dcl.run(true);

        address coreOwner = coreProxy.owner();

        VaultLib.Config[] memory vaultConfigs = new VaultLib.Config[](1);

        // Add native asset
        vaultConfigs[0] = VaultLib.Config({
            asset: Constants.NATIVE_ASSET_ADDR,
            decimals: 18,
            operator: operator,
            name: "NativeTestVault",
            symbol: "NTV",
            extraData: abi.encode(operator, nativeNodeImpl)
        });

        vm.startBroadcast(coreOwner);
        IKarakBaseVault[] memory vaults = coreProxy.deployVaults(vaultConfigs, nativeVaultImpl);
        vm.stopBroadcast();
        IKarakBaseVault nativeVault = vaults[0];
        console2.log("Native Vault (proxy):", address(nativeVault));

        vaultConfigs[0] = VaultLib.Config({
            asset: testERC20Addr,
            decimals: 6,
            operator: operator,
            name: "TestVault",
            symbol: "TV",
            extraData: "0x"
        });

        vm.startBroadcast(coreOwner);
        vaults = coreProxy.deployVaults(vaultConfigs, address(0));
        vm.stopBroadcast();
        console2.log("ERC20 Vault (proxy):", address(vaults[0]));

        // Write the deployment addresses to a file
        string memory deploymentJson = string.concat(
            '{"core":"',
            vm.toString(address(coreProxy)),
            '{"operator":"',
            vm.toString(address(this)),
            '", "vault":"',
            vm.toString(address(vaults[0])),
            '", "nativeVault":"',
            vm.toString(address(nativeVault)),
            '"}'
        );

        vm.writeFile("./anvil-deployment.json", deploymentJson);
    }
}
