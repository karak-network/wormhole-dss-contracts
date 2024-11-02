// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import "solady/src/utils/LibClone.sol";
import "solady/src/tokens/ERC4626.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import "../../src/Core.sol";
import "../../src/NativeNode.sol";
import "../../src/NativeVault.sol";
import "../helpers/ProxyDeployment.sol";
import "../../src/interfaces/Events.sol";
import "../../src/entities/VaultLib.sol";
import "../../src/interfaces/Constants.sol";
import "../../src/entities/NativeVaultLib.sol";
import "../../src/entities/BeaconProofsLib.sol";
import "../../src/interfaces/IKarakBaseVault.sol";

struct ValidatorFieldProof {
    bytes32 beaconStateRoot;
    bytes beaconStateRootProof;
    bytes32 blockHeaderRoot;
    uint64 slot;
    bytes32[] validatorFields;
    uint40 validatorIndex;
    bytes validatorProof;
    bytes32 validatorRoot;
}

struct ValidatorBalanceProof {
    bytes balanceProof;
    bytes32 balanceRoot;
    bytes32 beaconBlockRoot;
    bytes containerProof;
    bytes32 containerRoot;
    bytes32 validatorPubKey;
}

contract NativeVaultTest is Test {
    Core core;
    NativeNode nativeNode;
    NativeVault nativeVault;

    address manager = address(11);
    address operator = address(12);
    address proxyAdmin = address(14);
    address slashingVetoCommittee = address(15);

    ValidatorFieldProof validatorFieldProof;
    ValidatorFieldProof exitingValidatorProof;
    ValidatorBalanceProof validatorBalanceProof;
    ValidatorBalanceProof exitedValidatorProof;

    uint256 internal constant beaconGenesisTimestamp = 1606824023;
    address mockAddressOfNode = address(0xBA2045808FD6CA01eF620FaDf8C51E2d6d016072);
    uint256 internal constant validatorBalanceValue = 32169596058000000000;
    bytes32 internal constant STATE_SLOT = 0x0e977c4f52771ae90b9a885786536a06e14de7815be95b6ed56cdea86f6fc300;
    bytes32 nodeToOwnerSlot = bytes32(uint256(STATE_SLOT) + 2);
    bytes32 ownerToNodeSlot = bytes32(uint256(STATE_SLOT) + 3);

    receive() external payable {}

    function setUp() public {
        vm.etch(
            Constants.BEACON_ROOTS_ADDRESS,
            hex"3373fffffffffffffffffffffffffffffffffffffffe14604d57602036146024575f5ffd5b5f35801560495762001fff810690815414603c575f5ffd5b62001fff01545f5260205ff35b5f5ffd5b62001fff42064281555f359062001fff015500"
        );
        // Setup core
        uint32 hookCallGasLimit = 500_000;
        uint32 hookGasBuffer = 40_000;
        uint32 supportsInterfaceGasLimit = 20_000;
        address nativeVaultImpl = address(new NativeVault());
        core = Core(ProxyDeployment.factoryDeploy(address(new Core()), proxyAdmin));
        core.initialize(
            nativeVaultImpl, manager, slashingVetoCommittee, hookCallGasLimit, supportsInterfaceGasLimit, hookGasBuffer
        );
        address[] memory assets = new address[](1);
        assets[0] = Constants.NATIVE_ASSET_ADDR;
        address[] memory slashingHandlers = new address[](1);
        slashingHandlers[0] = Constants.NATIVE_ASSET_ADDR;
        core.allowlistAssets(assets, slashingHandlers);

        // Setup NativeNode implementation
        address nativeNodeImpl = address(new NativeNode());

        // Deploy Vaults
        VaultLib.Config[] memory vaultConfigs = new VaultLib.Config[](1);
        vaultConfigs[0] = VaultLib.Config({
            asset: Constants.NATIVE_ASSET_ADDR,
            decimals: 18,
            operator: operator,
            name: "NativeTestVault",
            symbol: "NTV",
            extraData: abi.encode(address(manager), address(nativeNodeImpl))
        });

        vm.startPrank(operator);
        IKarakBaseVault[] memory vaults = core.deployVaults(vaultConfigs, address(0));
        nativeVault = NativeVault(address(vaults[0]));
        vm.stopPrank();

        string memory root = vm.projectRoot();
        string memory filename = "validator_field_data";
        string memory path = string.concat(root, "/test/fixtures/", filename, ".json");
        string memory file = vm.readFile(path);
        bytes memory parsed = vm.parseJson(file);
        validatorFieldProof = abi.decode(parsed, (ValidatorFieldProof));

        filename = "exiting_data";
        path = string.concat(root, "/test/fixtures/", filename, ".json");
        file = vm.readFile(path);
        parsed = vm.parseJson(file);
        exitingValidatorProof = abi.decode(parsed, (ValidatorFieldProof));

        filename = "balance_proof";
        path = string.concat(root, "/test/fixtures/", filename, ".json");
        file = vm.readFile(path);
        parsed = vm.parseJson(file);
        validatorBalanceProof = abi.decode(parsed, (ValidatorBalanceProof));

        filename = "exited_proof";
        path = string.concat(root, "/test/fixtures/", filename, ".json");
        file = vm.readFile(path);
        parsed = vm.parseJson(file);
        exitedValidatorProof = abi.decode(parsed, (ValidatorBalanceProof));
    }

    function slotTimestamp(uint64 slot) public pure returns (uint256) {
        return beaconGenesisTimestamp + ((slot + 1) * 12);
    }

    function timestamp_idx(uint256 timestamp) public pure returns (bytes32) {
        return bytes32(uint256(timestamp % Constants.BEACON_ROOTS_RING_BUFFER));
    }

    function root_idx(uint256 timestamp) public pure returns (bytes32) {
        return bytes32(uint256(timestamp % Constants.BEACON_ROOTS_RING_BUFFER + Constants.BEACON_ROOTS_RING_BUFFER));
    }

    function calculateWithdrawKey(address nodeOwner, uint256 nodeOwnerNonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(nodeOwner, nodeOwnerNonce));
    }

    function prepareCredentialProof(ValidatorFieldProof memory proofs)
        public
        returns (BeaconProofs.ValidatorFieldsProof[] memory, BeaconProofs.BeaconStateRootProof memory)
    {
        BeaconProofs.ValidatorProof memory validatorProof = BeaconProofs.ValidatorProof({
            validatorIndex: proofs.validatorIndex,
            validatorRoot: proofs.validatorRoot,
            proof: proofs.validatorProof
        });
        BeaconProofs.ValidatorFieldsProof[] memory validatorFieldsProof = new BeaconProofs.ValidatorFieldsProof[](1);
        validatorFieldsProof[0] =
            BeaconProofs.ValidatorFieldsProof({validatorFields: proofs.validatorFields, validatorProof: validatorProof});

        BeaconProofs.BeaconStateRootProof memory beaconStateRootProof = BeaconProofs.BeaconStateRootProof({
            timestamp: uint64(slotTimestamp(validatorFieldProof.slot)),
            beaconStateRoot: proofs.beaconStateRoot,
            proof: proofs.beaconStateRootProof
        });

        vm.etch(address(mockAddressOfNode), type(NativeNode).runtimeCode);
        vm.store(
            address(nativeVault),
            keccak256(abi.encode(address(this), ownerToNodeSlot)),
            bytes32(abi.encode(mockAddressOfNode))
        );
        vm.store(
            Constants.BEACON_ROOTS_ADDRESS,
            timestamp_idx(beaconStateRootProof.timestamp),
            bytes32(uint256(beaconStateRootProof.timestamp))
        );
        vm.store(Constants.BEACON_ROOTS_ADDRESS, root_idx(beaconStateRootProof.timestamp), proofs.blockHeaderRoot);

        return (validatorFieldsProof, beaconStateRootProof);
    }

    function test_initialize_fail_reinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        nativeVault.initialize(address(core), operator, address(0), "ABCDE", "EFG", bytes(""));
    }

    function test_deposit_revert(uint256 amount, address to) public {
        vm.expectRevert(NotImplemented.selector);
        nativeVault.deposit(amount, to);
    }

    function test_mint_revert(uint256 shares, address to) public {
        vm.expectRevert(NotImplemented.selector);
        nativeVault.mint(shares, to);
    }

    function test_transfer_revert(address to, uint256 amount) public {
        vm.expectRevert(NotImplemented.selector);
        nativeVault.transfer(to, amount);
    }

    function test_transferFrom_revert(address from, address to, uint256 amount) public {
        vm.expectRevert(NotImplemented.selector);
        nativeVault.transferFrom(from, to, amount);
    }

    function test_withdraw_revert(uint256 assets, address to, address owner) public {
        vm.expectRevert(NotImplemented.selector);
        nativeVault.withdraw(assets, to, owner);
    }

    function test_redeem_revert(uint256 shares, address to, address owner) public {
        vm.expectRevert(NotImplemented.selector);
        nativeVault.redeem(shares, to, owner);
    }

    function test_createNode_duplicate_revert() public {
        nativeVault.createNode();
        vm.expectRevert(LibClone.DeploymentFailed.selector);
        nativeVault.createNode();
    }

    function test_startSnapshot_notNodeOwner_revert(address attacker) public {
        vm.assume(attacker != address(this));
        nativeVault.createNode();
        vm.startPrank(attacker);
        vm.expectRevert(NotNodeOwner.selector);
        nativeVault.startSnapshot(false);
        vm.stopPrank();
    }

    function test_startSnapshot_noBalanceChange_revert() public {
        nativeVault.createNode();
        vm.expectRevert(NoBalanceUpdateToSnapshot.selector);
        nativeVault.startSnapshot(true);
    }

    function test_initialize() public view {
        assertEq(nativeVault.owner(), address(core));
        assertEq(nativeVault.asset(), Constants.NATIVE_ASSET_ADDR);
        assertEq(nativeVault.name(), "NativeTestVault");
        assertEq(nativeVault.symbol(), "NTV");
        assertEq(nativeVault.decimals(), 18);
    }

    function test_createNode(address nodeOwner) public {
        vm.startPrank(nodeOwner);
        address node = nativeVault.createNode();

        assertEq(nodeOwner, nativeVault.getNodeOwner(node));
        assertEq(0, nativeVault.withdrawableWei(nodeOwner));
        assertEq(0, nativeVault.currentSnapshotTimestamp(nodeOwner));
        assertEq(0, nativeVault.lastSnapshotTimestamp(nodeOwner));
        vm.stopPrank();
    }

    function test_validateWithdrawalCredentials_exiting() public {
        (
            BeaconProofs.ValidatorFieldsProof[] memory validatorFieldsProof,
            BeaconProofs.BeaconStateRootProof memory beaconStateRootProof
        ) = prepareCredentialProof(exitingValidatorProof);

        vm.expectRevert(ValidatorExiting.selector);
        nativeVault.validateWithdrawalCredentials(address(this), beaconStateRootProof, validatorFieldsProof);
        assertEq(nativeVault.activeValidatorCount(address(this)), 0);
        assertEq(nativeVault.balanceOf(address(this)), 0);
    }

    function test_validateWithdrawalCredentials_active() public {
        (
            BeaconProofs.ValidatorFieldsProof[] memory validatorFieldsProof,
            BeaconProofs.BeaconStateRootProof memory beaconStateRootProof
        ) = prepareCredentialProof(validatorFieldProof);

        nativeVault.validateWithdrawalCredentials(address(this), beaconStateRootProof, validatorFieldsProof);
        assertEq(nativeVault.activeValidatorCount(address(this)), 1);
        assertEq(nativeVault.balanceOf(address(this)), uint256(32 * 1 ether));

        vm.expectRevert(ValidatorAlreadyActive.selector);
        nativeVault.validateWithdrawalCredentials(address(this), beaconStateRootProof, validatorFieldsProof);
        assertEq(nativeVault.activeValidatorCount(address(this)), 1);
        assertEq(nativeVault.balanceOf(address(this)), uint256(32 * 1 ether));
    }

    function test_validateWithdrawalCredentials_wrong_creds(address nodeOwner) public {
        vm.assume(nodeOwner != address(this));
        vm.prank(nodeOwner);
        nativeVault.createNode();
        (
            BeaconProofs.ValidatorFieldsProof[] memory validatorFieldsProof,
            BeaconProofs.BeaconStateRootProof memory beaconStateRootProof
        ) = prepareCredentialProof(validatorFieldProof);

        vm.expectRevert(WithdrawalCredentialsMismatchWithNode.selector);
        nativeVault.validateWithdrawalCredentials(nodeOwner, beaconStateRootProof, validatorFieldsProof);
        assertEq(nativeVault.activeValidatorCount(address(this)), 0);
        assertEq(nativeVault.balanceOf(address(this)), 0);
    }

    function test_startSnapshot_no_validators(bytes32 parentRoot) public {
        vm.assume(parentRoot != bytes32(0));

        address node = nativeVault.createNode();
        assertEq(nativeVault.getNodeOwner(node), address(this));

        vm.store(Constants.BEACON_ROOTS_ADDRESS, timestamp_idx(block.timestamp), bytes32(uint256(block.timestamp)));
        vm.store(Constants.BEACON_ROOTS_ADDRESS, root_idx(block.timestamp), parentRoot);

        nativeVault.startSnapshot(false);

        // Both 0 since there is no active validators hence snapshot finalises on starting
        assertEq(nativeVault.currentSnapshotTimestamp(address(this)), 0);
        assertEq(nativeVault.currentSnapshot(address(this)).parentBeaconBlockRoot, 0);
    }

    function test_startSnapshot_same_block(bytes32 parentRoot) public {
        vm.assume(parentRoot != bytes32(0));

        test_startSnapshot_no_validators(parentRoot);

        vm.expectRevert(AttemptedSnapshotInSameBlock.selector);
        nativeVault.startSnapshot(false);
    }

    function test_startSnapshot_pending(bytes32 parentRoot) public {
        vm.assume(parentRoot != bytes32(0));

        test_startSnapshot(parentRoot);

        vm.expectRevert(PendingIncompleteSnapshot.selector);
        nativeVault.startSnapshot(false);
    }

    function test_startSnapshot_no_balance_update(bytes32 parentRoot) public {
        vm.assume(parentRoot != bytes32(0));

        test_startSnapshot_no_validators(parentRoot);

        vm.warp(10000000);
        vm.expectRevert(NoBalanceUpdateToSnapshot.selector);
        nativeVault.startSnapshot(true);
    }

    function test_startWithdrawal_notNodeOwner_rever(address attacker) public {
        vm.assume(attacker != address(this));
        test_validateWithdrawalCredentials();

        vm.prank(attacker);
        vm.expectRevert(NotNodeOwner.selector);
        nativeVault.startWithdrawal(attacker, 100 wei);
    }

    function test_startWithdrawal_withdraw_max() public {
        test_validateWithdrawalCredentials();

        vm.expectRevert(ERC4626.WithdrawMoreThanMax.selector);
        nativeVault.startWithdrawal(address(this), 100 wei);
    }

    function test_startWithdrawal_snapshot_expired(bytes32 parentRoot, uint256 time) public {
        vm.assume(time > 7 days);
        vm.assume(time < type(uint256).max - block.timestamp);

        test_startSnapshot_no_validators(parentRoot);

        vm.warp(block.timestamp + time);
        vm.expectRevert(SnapshotExpired.selector);
        nativeVault.startWithdrawal(address(this), 0 wei);
    }

    function test_finishWithdrawal_min_delay_revert(bytes32 parentRoot, uint256 amount) public {
        bytes32 withdrawalKey = test_startWithdrawal(parentRoot, amount);

        vm.expectRevert(MinWithdrawDelayNotPassed.selector);
        nativeVault.finishWithdrawal(withdrawalKey);
    }

    function test_finishWithdrawal_min_delay_revert(bytes32 withdrawKey) public {
        vm.expectRevert(WithdrawalNotFound.selector);
        nativeVault.finishWithdrawal(withdrawKey);
    }

    function test_validateWithdrawalCredentials() public {
        (
            BeaconProofs.ValidatorFieldsProof[] memory validatorFieldsProof,
            BeaconProofs.BeaconStateRootProof memory beaconStateRootProof
        ) = prepareCredentialProof(validatorFieldProof);

        nativeVault.validateWithdrawalCredentials(address(this), beaconStateRootProof, validatorFieldsProof);
        assertEq(nativeVault.activeValidatorCount(address(this)), 1);
        assertEq(nativeVault.balanceOf(address(this)), uint256(32 * 1 ether));
    }

    function test_startSnapshot(bytes32 parentRoot) public {
        vm.assume(parentRoot != bytes32(0));
        test_validateWithdrawalCredentials();

        address node = nativeVault.createNode();
        assertEq(nativeVault.getNodeOwner(node), address(this));

        vm.store(Constants.BEACON_ROOTS_ADDRESS, timestamp_idx(block.timestamp), bytes32(uint256(block.timestamp)));
        vm.store(Constants.BEACON_ROOTS_ADDRESS, root_idx(block.timestamp), parentRoot);

        nativeVault.startSnapshot(false);

        assertEq(nativeVault.currentSnapshotTimestamp(address(this)), block.timestamp);
        assertEq(nativeVault.currentSnapshot(address(this)).parentBeaconBlockRoot, parentRoot);
    }

    function test_startWithdrawal(bytes32 parentRoot, uint256 amount) public returns (bytes32) {
        vm.assume(parentRoot != bytes32(0));
        vm.assume(amount > 0);
        vm.assume(amount < uint256(type(int256).max));

        address node = nativeVault.createNode();
        assertEq(nativeVault.getNodeOwner(node), address(this));

        vm.store(Constants.BEACON_ROOTS_ADDRESS, timestamp_idx(block.timestamp), bytes32(uint256(block.timestamp)));
        vm.store(Constants.BEACON_ROOTS_ADDRESS, root_idx(block.timestamp), parentRoot);

        vm.deal(node, amount);

        nativeVault.startSnapshot(true);

        vm.expectEmit();
        emit StartedWithdraw(address(this), operator, calculateWithdrawKey(address(this), 0), amount, address(this));
        bytes32 withdrawalKey = nativeVault.startWithdrawal(address(this), amount);
        return withdrawalKey;
    }

    function test_finishWithdrawal(bytes32 parentRoot, uint256 amount) public {
        bytes32 withdrawalKey = test_startWithdrawal(parentRoot, amount);

        vm.warp(block.timestamp + Constants.MIN_WITHDRAWAL_DELAY);
        uint256 oldBalance = address(this).balance;
        nativeVault.finishWithdrawal(withdrawalKey);
        assertEq(address(this).balance, amount + oldBalance);
    }

    function test_validateSnapshotProof() public returns (address node) {
        test_validateWithdrawalCredentials();

        address node = nativeVault.createNode();
        assertEq(nativeVault.getNodeOwner(node), address(this));

        vm.store(Constants.BEACON_ROOTS_ADDRESS, timestamp_idx(block.timestamp), bytes32(uint256(block.timestamp)));
        vm.store(Constants.BEACON_ROOTS_ADDRESS, root_idx(block.timestamp), validatorBalanceProof.beaconBlockRoot);

        nativeVault.startSnapshot(false);

        BeaconProofs.BalanceProof[] memory snapshotBalanceProofs = new BeaconProofs.BalanceProof[](1);
        snapshotBalanceProofs[0] = BeaconProofs.BalanceProof({
            pubkeyHash: validatorBalanceProof.validatorPubKey,
            balanceRoot: validatorBalanceProof.balanceRoot,
            proof: validatorBalanceProof.balanceProof
        });

        BeaconProofs.BalanceContainer memory snapshotContainerProof = BeaconProofs.BalanceContainer({
            containerRoot: validatorBalanceProof.containerRoot,
            proof: validatorBalanceProof.containerProof
        });

        assertEq(nativeVault.balanceOf(address(this)), 32000000000000000000);
        assertEq(nativeVault.currentSnapshotTimestamp(address(this)), 1);
        nativeVault.validateSnapshotProofs(address(this), snapshotBalanceProofs, snapshotContainerProof);

        assertEq(nativeVault.balanceOf(address(this)), validatorBalanceValue);
        assertEq(nativeVault.currentSnapshotTimestamp(address(this)), 0);

        return node;
    }

    function test_validateSnapshotProof_exitedValidator(uint64 warpTime) public {
        vm.assume(warpTime > 0);
        vm.assume(warpTime < type(uint64).max - block.timestamp);

        address node = test_validateSnapshotProof();

        vm.warp(block.timestamp + warpTime);

        vm.store(Constants.BEACON_ROOTS_ADDRESS, timestamp_idx(block.timestamp), bytes32(uint256(block.timestamp)));
        vm.store(Constants.BEACON_ROOTS_ADDRESS, root_idx(block.timestamp), exitedValidatorProof.beaconBlockRoot);

        vm.deal(node, validatorBalanceValue);

        uint256 oldShares = nativeVault.balanceOf(address(this));
        nativeVault.startSnapshot(false);

        BeaconProofs.BalanceProof[] memory snapshotBalanceProofs = new BeaconProofs.BalanceProof[](1);
        snapshotBalanceProofs[0] = BeaconProofs.BalanceProof({
            pubkeyHash: exitedValidatorProof.validatorPubKey,
            balanceRoot: exitedValidatorProof.balanceRoot,
            proof: exitedValidatorProof.balanceProof
        });

        BeaconProofs.BalanceContainer memory snapshotContainerProof = BeaconProofs.BalanceContainer({
            containerRoot: exitedValidatorProof.containerRoot,
            proof: exitedValidatorProof.containerProof
        });

        nativeVault.validateSnapshotProofs(address(this), snapshotBalanceProofs, snapshotContainerProof);

        assertEq(nativeVault.balanceOf(address(this)), oldShares);
        assertEq(nativeVault.activeValidatorCount(address(this)), 0);
        assertEq(nativeVault.currentSnapshotTimestamp(address(this)), 0);
    }

    function test_slashAssets(uint256 amount, uint256 slashAmount, uint64 warpTime) public {
        vm.assume(amount < type(uint256).max / 2);
        vm.assume(warpTime > 0);
        vm.assume(warpTime < type(uint64).max - block.timestamp);

        test_validateWithdrawalCredentials();

        address node = nativeVault.createNode();
        assertEq(nativeVault.getNodeOwner(node), address(this));

        vm.store(Constants.BEACON_ROOTS_ADDRESS, timestamp_idx(block.timestamp), bytes32(uint256(block.timestamp)));
        vm.store(Constants.BEACON_ROOTS_ADDRESS, root_idx(block.timestamp), validatorBalanceProof.beaconBlockRoot);

        vm.deal(node, amount);
        nativeVault.startSnapshot(false);

        BeaconProofs.BalanceProof[] memory snapshotBalanceProofs = new BeaconProofs.BalanceProof[](1);
        snapshotBalanceProofs[0] = BeaconProofs.BalanceProof({
            pubkeyHash: validatorBalanceProof.validatorPubKey,
            balanceRoot: validatorBalanceProof.balanceRoot,
            proof: validatorBalanceProof.balanceProof
        });

        BeaconProofs.BalanceContainer memory snapshotContainerProof = BeaconProofs.BalanceContainer({
            containerRoot: validatorBalanceProof.containerRoot,
            proof: validatorBalanceProof.containerProof
        });

        assertEq(nativeVault.balanceOf(address(this)), 32000000000000000000);
        assertEq(nativeVault.currentSnapshotTimestamp(address(this)), 1);
        nativeVault.validateSnapshotProofs(address(this), snapshotBalanceProofs, snapshotContainerProof);

        assertEq(nativeVault.balanceOf(address(this)), validatorBalanceValue + amount);
        assertEq(nativeVault.currentSnapshotTimestamp(address(this)), 0);

        uint256 oldAssets = nativeVault.convertToAssets(nativeVault.balanceOf(address(this)));
        uint256 oldTotal = nativeVault.totalAssets();
        uint256 oldShares = nativeVault.balanceOf(address(this));

        assertEq(oldTotal, validatorBalanceValue + amount);
        assertEq(oldAssets, validatorBalanceValue + amount);

        vm.prank(address(core));
        nativeVault.slashAssets(slashAmount, address(0));

        assertEq(nativeVault.totalAssets(), oldTotal - Math.min(slashAmount, oldTotal));
        assertEq(
            nativeVault.convertToAssets(nativeVault.balanceOf(address(this))),
            oldAssets - Math.min(slashAmount, oldTotal)
        );

        vm.warp(block.timestamp + warpTime);

        vm.store(Constants.BEACON_ROOTS_ADDRESS, timestamp_idx(block.timestamp), bytes32(uint256(block.timestamp)));
        vm.store(Constants.BEACON_ROOTS_ADDRESS, root_idx(block.timestamp), validatorBalanceProof.beaconBlockRoot);

        vm.expectEmit();
        emit NodeETHWithdrawn(address(node), address(0), Math.min(node.balance, slashAmount));
        nativeVault.startSnapshot(false);

        snapshotBalanceProofs = new BeaconProofs.BalanceProof[](1);
        snapshotBalanceProofs[0] = BeaconProofs.BalanceProof({
            pubkeyHash: validatorBalanceProof.validatorPubKey,
            balanceRoot: validatorBalanceProof.balanceRoot,
            proof: validatorBalanceProof.balanceProof
        });

        snapshotContainerProof = BeaconProofs.BalanceContainer({
            containerRoot: validatorBalanceProof.containerRoot,
            proof: validatorBalanceProof.containerProof
        });

        nativeVault.validateSnapshotProofs(address(this), snapshotBalanceProofs, snapshotContainerProof);

        assertEq(nativeVault.balanceOf(address(this)), oldShares);
        assertEq(
            nativeVault.convertToAssets(nativeVault.balanceOf(address(this))),
            oldAssets - Math.min(slashAmount, oldTotal)
        );
        assertEq(nativeVault.currentSnapshotTimestamp(address(this)), 0);
    }
}
