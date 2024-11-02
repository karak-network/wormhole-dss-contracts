// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";

import {Core, VaultLib} from "../../src/Core.sol";
import {IKarakBaseVault} from "../../src/interfaces/IKarakBaseVault.sol";

contract DeployVaults is Script {
    struct VaultConfig {
        uint8 decimals;
        string name;
        string symbol;
        address token;
    }

    struct AssetData {
        string name;
        address slashingHandler;
        address token;
    }

    struct AssetDataList {
        AssetData[] assetData;
        address core;
    }

    struct VaultDataList {
        address core;
        VaultConfig[] vaultData;
    }

    // Add operator address here
    address internal constant OPERATOR = 0x0000000000000000000000000000000000000000;
    string internal constant VAULT_CONFIG_PATH_PREFIX = "/script/v2/config/vault_config_";
    string internal constant ASSET_CONFIG_PATH_PREFIX = "/script/v2/config/asset_config_";
    Core internal core;

    /**
     * @notice Reads vault data from the config/vault_config_<chainName>.json, and deploys the vaults for OPERATOR.
     */
    function run() public {
        VaultLib.Config[] memory vaultConfigs = fetchVaultConfigs();
        vm.startBroadcast(OPERATOR);
        IKarakBaseVault[] memory vaults = core.deployVaults(vaultConfigs, address(0));
        vm.stopBroadcast();
        for (uint256 i = 0; i < vaults.length; i++) {
            console2.log("\tDeployed Vault:", address(vaults[i]), "for asset:", vaultConfigs[i].asset);
            console2.log();
        }
    }

    /**
     * @notice Reads asset data from the config/asset_config_<chainName>.json, and allowlists assets with their corresponding slashing handlers
     */
    function allowlistAssets() public {
        string memory fileName = getAssetDataListFilename();
        string memory file = vm.readFile(fileName);
        bytes memory parsed = vm.parseJson(file);
        AssetDataList memory assetDataList = abi.decode(parsed, (AssetDataList));
        core = Core(assetDataList.core);

        address[] memory assets = new address[](assetDataList.assetData.length);
        address[] memory slashingHandlers = new address[](assetDataList.assetData.length);
        for (uint256 i = 0; i < assetDataList.assetData.length; i++) {
            assets[i] = assetDataList.assetData[i].token;
            slashingHandlers[i] = assetDataList.assetData[i].slashingHandler;
        }
        vm.startBroadcast(core.owner());
        core.allowlistAssets(assets, slashingHandlers);
        vm.stopBroadcast();
    }

    function fetchVaultConfigs() internal returns (VaultLib.Config[] memory vaultConfigs) {
        string memory fileName = getVaultDataListFilename();
        string memory file = vm.readFile(fileName);
        bytes memory parsed = vm.parseJson(file);
        VaultDataList memory vaultDataList = abi.decode(parsed, (VaultDataList));
        core = Core(vaultDataList.core);
        vaultConfigs = new VaultLib.Config[](vaultDataList.vaultData.length);

        for (uint256 i = 0; i < vaultDataList.vaultData.length; i++) {
            vaultConfigs[i] = VaultLib.Config({
                asset: vaultDataList.vaultData[i].token,
                name: vaultDataList.vaultData[i].name,
                symbol: vaultDataList.vaultData[i].symbol,
                operator: OPERATOR,
                decimals: vaultDataList.vaultData[i].decimals,
                extraData: ""
            });
        }
    }

    function getVaultDataListFilename() internal view returns (string memory fileName) {
        fileName = string.concat(vm.projectRoot(), VAULT_CONFIG_PATH_PREFIX, getChainName(), ".json");
    }

    function getAssetDataListFilename() internal view returns (string memory fileName) {
        fileName = string.concat(vm.projectRoot(), ASSET_CONFIG_PATH_PREFIX, getChainName(), ".json");
    }

    function getChainName() internal view returns (string memory chainName) {
        if (block.chainid == 1) {
            chainName = "mainnet";
        } else if (block.chainid == 42161) {
            chainName = "arbitrum";
        } else if (block.chainid == 2410) {
            chainName = "karak";
        } else if (block.chainid == 5000) {
            chainName = "mantle";
        } else if (block.chainid == 56) {
            chainName = "bsc";
        } else if (block.chainid == 81457) {
            chainName = "mantle";
        } else {
            revert MAKE_SURE_ALL_CHAINS_ARE_ADDED();
        }
    }

    error MAKE_SURE_ALL_CHAINS_ARE_ADDED();
}
