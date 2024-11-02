// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

//helper function to register a DSS as a contract.
import {Core} from "../../src/Core.sol";

contract MockDSS {
    function registerSelf(Core core, uint256 maxSlashablePercentageWad) external {
        core.registerDSS(maxSlashablePercentageWad);
    }

    receive() external payable {}
}
