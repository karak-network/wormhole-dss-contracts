// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "../../src/interfaces/IVault.sol";

//tracks "Vault:StartedRedeem"
contract StartRedeemScript is Script {
    address private constant VAULT_ADDRESS = 0xc99B9A9579e863387D1a07c3B0bdCA430B2e7d35;
    address private constant TOKEN_ADDRESS = 0x8A791620dd6260079BF849Dc5567aDC3F2FdC318;
    address private constant USER_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 private constant REDEEM_AMOUNT = 1000;

    function run() external {
        vm.startBroadcast();

        IVault vault = IVault(VAULT_ADDRESS);
        IERC20 token = IERC20(TOKEN_ADDRESS);
        IERC20 vaultToken = IERC20(VAULT_ADDRESS);

        uint256 initialTokenBalance = token.balanceOf(USER_ADDRESS);
        uint256 initialShares = vaultToken.balanceOf(USER_ADDRESS);
        console2.log("Initial token balance:", initialTokenBalance);
        console2.log("Initial shares balance:", initialShares);

        console2.log("Approving vault to transfer shares...");
        vaultToken.approve(VAULT_ADDRESS, REDEEM_AMOUNT);
        uint256 allowance = vaultToken.allowance(USER_ADDRESS, VAULT_ADDRESS);
        console2.log("Share allowance:", allowance);

        console2.log("Starting redeem process...");
        uint256 startBlock = block.number;
        uint256 startTimestamp = block.timestamp;
        console2.log("Start block:", startBlock);
        console2.log("Start timestamp:", startTimestamp);

        bytes32 withdrawalKey;
        try vault.startRedeem(REDEEM_AMOUNT, USER_ADDRESS) returns (bytes32 key) {
            withdrawalKey = key;
            console2.log("Redeem started successfully. Withdrawal key:", uint256(withdrawalKey));
        } catch Error(string memory reason) {
            console2.log("Start redeem failed with reason:", reason);
            vm.stopBroadcast();
            return;
        }

        uint256 nonce = vault.getNextWithdrawNonce(USER_ADDRESS);
        console2.log("Next withdraw nonce:", nonce);

        vm.stopBroadcast();
    }
}
