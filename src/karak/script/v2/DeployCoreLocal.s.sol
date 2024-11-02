// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Factory} from "solady/src/utils/ERC1967Factory.sol";
import {Core} from "../../src/Core.sol";
import {Vault} from "../../src/Vault.sol";
import {NativeVault} from "../../src/NativeVault.sol";
import {NativeNode} from "../../src/NativeNode.sol";
import {SlashingHandler} from "../../src/SlashingHandler.sol";
import {RestakingRegistry} from "../../src/registry/RestakingRegistry.sol";
import {ERC20Mintable} from "../../test/helpers/contracts/ERC20Mintable.sol";
import {Constants} from "../../src/interfaces/Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract DeployCoreLocal is Script {
    address internal constant CORE_PROXY_ADMIN = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address internal constant CORE_MANAGER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant CORE_VETO_COMMITTEE = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant SLASHING_HANDLER_PROXY_ADMIN = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address internal constant DEPLOYER = 0x54603E6fd3A92E32Bd3c00399D306B82bB3601Ba;
    address internal constant TIMELOCK_PROPOSER_EXECUTOR = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant TIMELOCK_EXECUTOR = 0x54603E6fd3A92E32Bd3c00399D306B82bB3601Ba;
    uint32 internal constant HOOK_CALL_GAS_LIMIT = 500_000;
    uint32 internal constant HOOK_GAS_BUFFER = 40_000;
    uint32 internal constant SUPPORTS_INTERFACE_GAS_LIMIT = 20_000;
    uint256 internal constant TIMELOCK_DELAY = 3 seconds;

    string internal JSON_NAME = "DeployCoreLocal";
    string internal CHAIN_NAME = "anvil";

    function run(bool isDevelopment)
        public
        returns (
            address coreImpl,
            address vaultImpl,
            address slashingHandlerImpl,
            address registryImpl,
            address nativeVaultImpl,
            address nativeNodeImpl,
            address testERC20Addr,
            Core coreProxy,
            RestakingRegistry registryProxy
        )
    {
        console2.log("Running DeployCoreLocal script. Signer:", msg.sender);
        console2.log();

        (coreImpl, vaultImpl, slashingHandlerImpl, registryImpl, nativeVaultImpl, nativeNodeImpl) = deployImpls();
        console2.log("Deployed Core(impl):", coreImpl);
        console2.log("Deployed Vault(impl):", vaultImpl);
        console2.log("Deployed SlashingHandler(impl):", slashingHandlerImpl);
        console2.log("Deployed Native Vault(impl):", nativeVaultImpl);
        console2.log("Deployed Native Node(impl):", nativeNodeImpl);
        console2.log();

        SlashingHandler slashingHandlerProxy;
        (coreProxy, slashingHandlerProxy, registryProxy) = deployProxies(coreImpl, slashingHandlerImpl, registryImpl);
        console2.log("Deployed Core(proxy):", address(coreProxy));
        console2.log("Deployed SlashingHandler(proxy):", address(slashingHandlerProxy));
        writeAddress("Core", address(coreProxy));
        writeAddress("SlashingHandler", address(slashingHandlerProxy));
        console2.log();

        initializeCore(coreProxy, vaultImpl);
        console2.log("Initialized Core(proxy) with params:");
        console2.log("\tVault Implementation:", vaultImpl);
        console2.log("\tManager:", CORE_MANAGER);
        console2.log("\tVeto Committee:", CORE_VETO_COMMITTEE);
        console2.log();

        initializeAncillary(registryProxy);
        console2.log("Initialized Registry(proxy) with params:");
        console2.log("\tManager:", CORE_MANAGER);
        writeAddress("Registry", address(registryProxy));
        console2.log();

        ERC20Mintable testERC20 = deployTestERC20();
        testERC20.mint(msg.sender, 1e6 * 1e6);
        console2.log("Deployed TEST ERC20:", address(testERC20));
        console2.log("Minted 1,000,000 TEST ERC20 to msg.sender");
        console2.log();

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(testERC20));

        initializeSlashingHandler(slashingHandlerProxy, tokens);
        console2.log("Initialized SlashingHandler(proxy) with params:");
        console2.log("\tTokens:");
        for (uint256 i = 0; i < tokens.length; i++) {
            console2.log("\t ", i, "-", address(tokens[i]));
        }

        address[] memory assets = new address[](2);
        address[] memory slashingHandlers = new address[](2);
        assets[0] = address(testERC20);
        slashingHandlers[0] = address(slashingHandlerProxy);
        // Add native ETH asset
        assets[1] = Constants.NATIVE_ASSET_ADDR;
        slashingHandlers[1] = Constants.NATIVE_ASSET_ADDR;

        allowlistAssets(coreProxy, assets, slashingHandlers);

        writeAddress("NativeVault", address(nativeVaultImpl));
        writeAddress("NativeNode", address(nativeNodeImpl));

        // add native vault impl
        vm.startBroadcast(coreProxy.owner());
        coreProxy.allowlistVaultImpl(nativeVaultImpl);
        vm.stopBroadcast();

        console2.log();

        if (!isDevelopment) {
            address timelock = deployTimelock(TIMELOCK_PROPOSER_EXECUTOR, TIMELOCK_EXECUTOR, TIMELOCK_DELAY);
            console2.log("Deployed timelock", address(timelock));
            writeAddress("Timelock", address(timelock));
            console2.log();

            vm.startBroadcast(coreProxy.owner());
            coreProxy.transferOwnership(timelock);
            vm.stopBroadcast();
            writeJson();
        }

        testERC20Addr = address(testERC20);
    }

    function deployImpls()
        public
        returns (
            address coreImpl,
            address vaultImpl,
            address slashingHandlerImpl,
            address registryImpl,
            address nativeVaultImpl,
            address nativeNodeImpl
        )
    {
        vm.startBroadcast();
        coreImpl = address(new Core());
        vaultImpl = address(new Vault());
        slashingHandlerImpl = address(new SlashingHandler());
        registryImpl = address(new RestakingRegistry());
        nativeVaultImpl = address(new NativeVault());
        nativeNodeImpl = address(new NativeNode());
        vm.stopBroadcast();
    }

    function deployProxies(address coreImpl, address slashingHandlerImpl, address registryImpl)
        public
        returns (Core coreProxy, SlashingHandler slashingHandlerProxy, RestakingRegistry registryProxy)
    {
        vm.startBroadcast();
        ERC1967Factory factory = new ERC1967Factory();
        coreProxy = Core(factory.deploy(coreImpl, CORE_PROXY_ADMIN));
        slashingHandlerProxy = SlashingHandler(factory.deploy(slashingHandlerImpl, SLASHING_HANDLER_PROXY_ADMIN));
        registryProxy = RestakingRegistry(factory.deploy(registryImpl, CORE_PROXY_ADMIN));
        vm.stopBroadcast();
    }

    function initializeCore(Core core, address vaultImpl) public {
        vm.startBroadcast();
        core.initialize(
            vaultImpl,
            CORE_MANAGER,
            CORE_VETO_COMMITTEE,
            HOOK_CALL_GAS_LIMIT,
            SUPPORTS_INTERFACE_GAS_LIMIT,
            HOOK_GAS_BUFFER
        );
        vm.stopBroadcast();
    }

    function initializeAncillary(RestakingRegistry registry) public {
        vm.startBroadcast();
        registry.initialize(CORE_MANAGER);
        vm.stopBroadcast();
    }

    function deployTestERC20() public returns (ERC20Mintable testERC20) {
        vm.startBroadcast();
        testERC20 = new ERC20Mintable();
        testERC20.initialize("Test", "TEST", 6);
        vm.stopBroadcast();
    }

    function initializeSlashingHandler(SlashingHandler slashingHandler, IERC20[] memory tokens) public {
        vm.startBroadcast();
        slashingHandler.initialize(msg.sender, tokens);
        vm.stopBroadcast();
    }

    function allowlistAssets(Core core, address[] memory assets, address[] memory slashingHandlers) public {
        vm.startBroadcast();
        core.allowlistAssets(assets, slashingHandlers);
        vm.stopBroadcast();
    }

    function writeAddress(string memory contractName, address addr) public {
        vm.serializeAddress(JSON_NAME, contractName, addr);
    }

    function writeJson() public {
        string memory finalJson = vm.serializeAddress(JSON_NAME, "Ignore", address(0));

        vm.writeJson(finalJson, string.concat("./deployments/", CHAIN_NAME, "/contracts.json"));
    }

    function deployTimelock(address timelockproposer, address executor, uint256 delay)
        public
        returns (address timelock)
    {
        vm.startBroadcast(DEPLOYER);
        address[] memory proposers = new address[](1);
        proposers[0] = timelockproposer;
        address[] memory executors = new address[](2);
        executors[0] = timelockproposer;
        executors[1] = executor;
        TimelockController _timelock = new TimelockController(delay, proposers, executors, address(0));
        vm.stopBroadcast();
        return address(_timelock);
    }
}
