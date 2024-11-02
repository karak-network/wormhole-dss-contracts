// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {ERC20Mintable} from "../../test/helpers/contracts/ERC20Mintable.sol";

//test script to test "Vault:Deposit"
contract CompleteDepositFlow is Script {
    address private constant VAULT_ADDRESS = 0xc99B9A9579e863387D1a07c3B0bdCA430B2e7d35;
    address private constant TOKEN_ADDRESS = 0x8A791620dd6260079BF849Dc5567aDC3F2FdC318;
    address private constant USER_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 private constant AMOUNT = 1000;

    function run() external {
        vm.startBroadcast();

        ERC20Mintable token = ERC20Mintable(TOKEN_ADDRESS);
        IVault vault = IVault(VAULT_ADDRESS);

        console2.log("Minting tokens...");
        token.mint(USER_ADDRESS, AMOUNT);
        console2.log("Tokens minted:", AMOUNT);

        uint256 balance = token.balanceOf(USER_ADDRESS);
        console2.log("Token balance after minting:", balance);

        console2.log("Approving Vault to spend tokens...");
        token.approve(VAULT_ADDRESS, AMOUNT);
        uint256 allowance = token.allowance(USER_ADDRESS, VAULT_ADDRESS);
        console2.log("Allowance:", allowance);

        console2.log("Depositing into Vault...");
        try vault.deposit(AMOUNT, USER_ADDRESS) returns (uint256 shares) {
            console2.log("Deposit successful, shares minted:", shares);
        } catch Error(string memory reason) {
            console2.log("Deposit failed with reason:", reason);
        } catch (bytes memory reason) {
            console2.log("Deposit failed with reason (bytes):");
            console2.logBytes(reason);
        }

        uint256 finalTokenBalance = token.balanceOf(USER_ADDRESS);
        console2.log("Final token balance:", finalTokenBalance);

        vm.stopBroadcast();
    }
}
