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

contract DeployCore is Script {
    address internal constant CORE_PROXY_ADMIN = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address internal constant CORE_MANAGER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant CORE_VETO_COMMITTEE = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant SLASHING_HANDLER_PROXY_ADMIN = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address internal constant NTT_MANAGER = 0x7324d9AD40b4990dE3EBadB0E9103C5A1366C228;

    function run() public {
        vm.startBroadcast();
        console2.log("Running DeployCoreLocal script. Signer:", msg.sender);
        console2.log();

        (address coreImpl, address vaultImpl, address slashingHandlerImpl) = deployImpls();
        console2.log("Deployed Core(impl):", coreImpl);
        console2.log("Deployed Vault(impl):", vaultImpl);
        console2.log("Deployed SlashingHandler(impl):", slashingHandlerImpl);
        console2.log();

        (Core coreProxy, SlashingHandler slashingHandlerProxy) = deployProxies(coreImpl, slashingHandlerImpl);
        console2.log("Deployed Core(proxy):", address(coreProxy));
        console2.log("Deployed SlashingHandler(proxy):", address(slashingHandlerProxy));
        console2.log();

        initializeCore(coreProxy, vaultImpl);
        console2.log("Initialized Core(proxy) with params:");
        console2.log("\tVault Implementation:", vaultImpl);
        console2.log("\tManager:", CORE_MANAGER);
        console2.log("\tVeto Committee:", CORE_VETO_COMMITTEE);
        console2.log();

        ERC20Mintable testERC20 = deployTestERC20();

        testERC20.mint(msg.sender, 1e6 * 1e6);
        console2.log("Deployed TEST ERC20:", address(testERC20));
        console2.log("Minted ", testERC20.balanceOf(msg.sender), " TEST ERC20 to ", msg.sender);
        console2.log();

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(testERC20));

        initializeSlashingHandler(slashingHandlerProxy, tokens);
        console2.log("Initialized SlashingHandler(proxy) with params:");
        console2.log("\tTokens:");
        for (uint256 i = 0; i < tokens.length; i++) {
            console2.log("\t ", i, "-", address(tokens[i]));
        }
        console2.log();

        allowListAsset(address(coreProxy), address(testERC20), address(slashingHandlerProxy), address(vaultImpl));

        vm.stopBroadcast();
    }

    function deployImpls() public returns (address coreImpl, address vaultImpl, address slashingHandlerImpl) {
        coreImpl = address(new Core());
        vaultImpl = address(new Vault());
        slashingHandlerImpl = address(new SlashingHandler());
    }

    function deployProxies(address coreImpl, address slashingHandlerImpl)
        public
        returns (Core coreProxy, SlashingHandler slashingHandlerProxy)
    {
        ERC1967Factory factory = new ERC1967Factory();
        coreProxy = Core(factory.deploy(coreImpl, CORE_PROXY_ADMIN));
        slashingHandlerProxy = SlashingHandler(factory.deploy(slashingHandlerImpl, SLASHING_HANDLER_PROXY_ADMIN));
    }

    function initializeCore(Core core, address vaultImpl) public {
        core.initialize(vaultImpl, CORE_MANAGER, CORE_VETO_COMMITTEE, 10000000, 10000000, 1000000);
    }

    function deployTestERC20() public returns (ERC20Mintable testERC20) {
        testERC20 = new ERC20Mintable();
        testERC20.initialize("Test", "TEST", 6);
    }

    function initializeSlashingHandler(SlashingHandler slashingHandler, IERC20[] memory tokens) public {
        slashingHandler.initialize(msg.sender, tokens);
    }

    function allowListAsset(address coreProxy, address erc20Token, address slashingHandler, address vaultImpl)
        public
        returns (address vaultAddress)
    {
        address[] memory assets = new address[](1);
        assets[0] = erc20Token;
        address[] memory slashingHandlers = new address[](1);
        slashingHandlers[0] = slashingHandler;

        Core(coreProxy).allowlistAssets(assets, slashingHandlers);
    }

    function deployDSS(address core) public returns (WormholeDSS dss) {
        dss = new WormholeDSS();
        dss.initialize(ICore(core), 0);
        dss.registerDSS(10e18);
    }

    function deployTransceiver(address nttManger, address dss) public returns (WormholeDSSTransceiver transceiver) {
        transceiver = new WormholeDSSTransceiver();
        transceiver.initialize(nttManger, dss);
    }
}
