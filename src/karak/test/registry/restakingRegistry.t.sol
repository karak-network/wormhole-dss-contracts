// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {RestakingRegistry, KNSData} from "../../src/registry/RestakingRegistry.sol";
import "../helpers/ProxyDeployment.sol";

contract RestakingRegistryTest is Test {
    RestakingRegistry registry;
    address owner;
    address user1;
    address user2;

    function setUp() public {
        owner = address(this);
        user1 = address(1);
        user2 = address(2);
        address registryImpl = address(new RestakingRegistry());
        registry = RestakingRegistry(ProxyDeployment.factoryDeploy(registryImpl, owner));
        registry.initialize(owner);
    }

    function testOwnership() public {
        assertEq(registry.owner(), owner);
    }

    function testValidRegistration() public {
        string memory validKns = "v1.polygon.mainnet.dss.example.com";
        vm.prank(user1);
        registry.register(validKns, address(3), user1);

        (address entity, address knsOwner) = registry.getKns(validKns);
        assertEq(entity, address(3));
        assertEq(knsOwner, user1);
    }

    function testInvalidKnsFormat() public {
        string memory invalidKns = "invalid.kns.format";
        vm.expectRevert(abi.encodeWithSignature("UnexpectedAmtOfDots(uint256)", 2));
        registry.register(invalidKns, address(3), user1);
    }

    function testInvalidFourthSegment() public {
        string memory invalidKns = "v1.polygon.mainnet.invalid.example.com";
        vm.expectRevert(abi.encodeWithSignature("InvalidFourthSegment(string)", "invalid"));
        registry.register(invalidKns, address(3), user1);
    }

    function testZeroAddressRegistration() public {
        string memory validKns = "v1.polygon.mainnet.dss.example.com";
        vm.expectRevert(RestakingRegistry.AddressZero.selector);
        registry.register(validKns, address(0), user1);

        vm.expectRevert(RestakingRegistry.AddressZero.selector);
        registry.register(validKns, address(3), address(0));
    }

    function testUpdateExistingKns() public {
        string memory validKns = "v1.polygon.mainnet.dss.example.com";
        vm.prank(user1);
        registry.register(validKns, address(3), user1);

        vm.prank(user1);
        registry.register(validKns, address(4), user1);

        (address entity, address knsOwner) = registry.getKns(validKns);
        assertEq(entity, address(0x4));
        assertEq(knsOwner, user1);
    }

    function testUnauthorizedUpdate() public {
        string memory validKns = "v1.polygon.mainnet.dss.example.com";
        vm.prank(user1);
        registry.register(validKns, address(3), user1);

        vm.prank(user2);
        vm.expectRevert(RestakingRegistry.NotKnsOwner.selector);
        registry.register(validKns, address(4), user2);
    }

    function testValidKnsFormats() public {
        string[3] memory validFormats =
            ["v1.polygon.mainnet.dss.example.com", "2.1.0.operator.test.net", "3.2.1.vault.domain.org"];

        for (uint256 i = 0; i < validFormats.length; i++) {
            assertTrue(registry.validateKNSFormat(validFormats[i]));
        }
    }

    function testInvalidKnsFormats() public {
        string[2] memory invalidFormats = ["v1.polygon.mainnet.invalid.example.com", "v1.0.dss.example.com"];

        for (uint256 i = 0; i < invalidFormats.length; i++) {
            vm.expectRevert();
            registry.validateKNSFormat(invalidFormats[i]);
        }
    }

    function testEmitKnsUpdatedEvent() public {
        string memory validKns = "v1.po.go.dss.example.com";
        address entity = address(3);

        vm.expectEmit(true, true, true, true);
        emit RestakingRegistry.KnsUpdated(validKns, entity, user1);

        vm.prank(user1);
        registry.register(validKns, entity, user1);
    }

    function testAdminOverride() public {
        string memory validKns = "v1.polygon.mainnet.dss.example.com";
        vm.prank(user1);
        registry.register(validKns, address(3), user1);

        vm.prank(owner);
        registry.overrideKns(validKns, KNSData(address(4), owner));

        (address entity, address knsOwner) = registry.getKns(validKns);
        assertEq(entity, address(4));
        assertEq(knsOwner, owner);
    }
}
