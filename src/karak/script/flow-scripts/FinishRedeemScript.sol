// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "../../src/interfaces/IVault.sol";

//tracks "Vault:FinsihedRedeem"
contract FinishRedeemScript is Script {
    address private constant VAULT_ADDRESS = 0x994B6a2Edda7785fE2b5072Ad89A572423a37D24;
    address private constant TOKEN_ADDRESS = 0x8A791620dd6260079BF849Dc5567aDC3F2FdC318;
    address private constant USER_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function run() external {
        vm.startBroadcast();

        IVault vault = IVault(VAULT_ADDRESS);
        IERC20 token = IERC20(TOKEN_ADDRESS);
        IERC20 vaultToken = IERC20(VAULT_ADDRESS);

        uint256 currentTimestamp = block.timestamp;
        uint256 currentBlock = block.number;
        console2.log("Current timestamp:", currentTimestamp);
        console2.log("Current block:", currentBlock);

        uint256 nonce = vault.getNextWithdrawNonce(USER_ADDRESS) - 1;
        console2.log("Withdraw nonce:", nonce);

        console2.log("Checking withdrawal status...");
        bool isReady = vault.isWithdrawalPending(USER_ADDRESS, nonce);
        console2.log("Withdrawal pending:", isReady);

        if (!isReady) {
            console2.log("Withdrawal is not ready. Aborting.");
            vm.stopBroadcast();
            return;
        }

        console2.log("Finishing redeem process...");
        // This is hardcoded, will have to change this everytime you trigger StartRedeem. pass the key from the event logs
        bytes32 withdrawalKey = 0x723077b8a1b173adc35e5f0e7e3662fd1208212cb629f9c128551ea7168da722;
        try vault.finishRedeem(withdrawalKey) {
            console2.log("Redeem finished successfully");
        } catch Error(string memory reason) {
            console2.log("Finish redeem failed with reason:", reason);
            vm.stopBroadcast();
            return;
        }

        uint256 finalTokenBalance = token.balanceOf(USER_ADDRESS);
        uint256 finalShares = vaultToken.balanceOf(USER_ADDRESS);
        console2.log("Final token balance:", finalTokenBalance);
        console2.log("Final shares balance:", finalShares);

        vm.stopBroadcast();
    }
}
