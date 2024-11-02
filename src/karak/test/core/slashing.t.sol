// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import "../helpers/OperatorHelper.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "../../src/entities/CoreStorageSlots.sol";

contract SlashingTests is OperatorHelper {
    function test_slash_operator(uint96 slashPercentageWad) public {
        vm.assume(
            slashPercentageWad > Constants.ONE_WAD && slashPercentageWad <= core.getDssMaxSlashablePercentageWad(dss)
        );
        stake_vaults_to_dss();

        vm.prank(operator);
        core.registerOperatorToDSS(dss2, "");
        uint96[] memory slashPercentagesWad = new uint96[](vaults.length);
        slashPercentagesWad[0] = slashPercentageWad;
        // Generate nonequal percentages
        uint96 slashPercentageWad1 =
            (slashPercentageWad + uint96(10 * Constants.ONE_WAD)) % uint96(core.getDssMaxSlashablePercentageWad(dss));
        // Make sure zero is not passed
        slashPercentageWad1 = slashPercentageWad1 == 0 ? slashPercentageWad1 : uint96(Constants.ONE_WAD);
        slashPercentagesWad[1] = slashPercentageWad1;

        vm.startPrank(address(dss));
        address[] memory operatorVaults = core.fetchVaultsStakedInDSS(operator, dss);

        SlasherLib.SlashRequest memory slashingReq = SlasherLib.SlashRequest({
            operator: operator,
            slashPercentagesWad: slashPercentagesWad,
            vaults: operatorVaults
        });

        SlasherLib.QueuedSlashing memory queuedSlashing = core.requestSlashing(slashingReq);

        // validate QueuedSlashing params
        assertEq(queuedSlashing.operator, slashingReq.operator);
        assertEq(keccak256(abi.encode(queuedSlashing.vaults)), keccak256(abi.encode(slashingReq.vaults)));
        assertEq(
            keccak256(abi.encode(queuedSlashing.slashPercentagesWad)),
            keccak256(abi.encode(slashingReq.slashPercentagesWad))
        );
        assertEq(queuedSlashing.timestamp, block.timestamp);
        assertEq(queuedSlashing.nonce, _getNonce() - 1);

        vm.warp(block.timestamp + Constants.SLASHING_VETO_WINDOW);

        uint256[] memory postSlashedAssets = new uint256[](operatorVaults.length);
        for (uint256 i = 0; i < operatorVaults.length; i++) {
            postSlashedAssets[i] = compute_post_slashed_assets_in_vault(operatorVaults[i], slashPercentagesWad[i]);
        }

        for (uint256 i = 0; i < operatorVaults.length; i++) {
            assertTrue(core.isVaultQueuedForSlashing(operatorVaults[i]));
            assertEq(_queuedSlashingCount(operator, operatorVaults[i]), 1);
        }
        core.finalizeSlashing(queuedSlashing);

        for (uint256 i = 0; i < operatorVaults.length; i++) {
            assertFalse(core.isVaultQueuedForSlashing(operatorVaults[i]));
            assertEq(_queuedSlashingCount(operator, operatorVaults[i]), 0);
        }
        for (uint256 i = 0; i < operatorVaults.length; i++) {
            assertEq(IVault(operatorVaults[i]).totalAssets(), postSlashedAssets[i]);
        }
        vm.stopPrank();
    }

    function test_slash_operator_skip_unstaked_vaults(uint96 slashPercentageWad) public {
        vm.assume(
            slashPercentageWad > Constants.ONE_WAD && slashPercentageWad <= core.getDssMaxSlashablePercentageWad(dss)
        );
        stake_vaults_to_dss();

        vm.prank(operator);
        core.registerOperatorToDSS(dss2, "");
        uint96[] memory slashPercentagesWad = new uint96[](vaults.length);
        slashPercentagesWad[0] = slashPercentageWad;
        // Generate nonequal percentages
        uint96 slashPercentageWad1 =
            (slashPercentageWad + uint96(10 * Constants.ONE_WAD)) % uint96(core.getDssMaxSlashablePercentageWad(dss));
        // Make sure zero is not passed
        slashPercentageWad1 = slashPercentageWad1 == 0 ? slashPercentageWad1 : uint96(Constants.ONE_WAD);
        slashPercentagesWad[1] = slashPercentageWad1;

        vm.startPrank(address(dss));
        address[] memory operatorVaults = core.fetchVaultsStakedInDSS(operator, dss);

        SlasherLib.SlashRequest memory slashingReq = SlasherLib.SlashRequest({
            operator: operator,
            slashPercentagesWad: slashPercentagesWad,
            vaults: operatorVaults
        });

        SlasherLib.QueuedSlashing memory queuedSlashing = core.requestSlashing(slashingReq);

        address unstakedVault = operatorVaults[0];

        update_vault_stake_to_dss(unstakedVault, false, dss);

        vm.warp(block.timestamp + Constants.SLASHING_VETO_WINDOW);

        uint256[] memory postSlashedAssets = new uint256[](operatorVaults.length);
        for (uint256 i = 0; i < operatorVaults.length; i++) {
            postSlashedAssets[i] = (operatorVaults[i] == unstakedVault)
                ? IVault(operatorVaults[i]).totalAssets()
                : compute_post_slashed_assets_in_vault(operatorVaults[i], slashPercentagesWad[i]);
        }

        vm.expectEmit();
        emit SkippedSlashing(unstakedVault);
        core.finalizeSlashing(queuedSlashing);
        for (uint256 i = 0; i < operatorVaults.length; i++) {
            assertEq(IVault(operatorVaults[i]).totalAssets(), postSlashedAssets[i]);
        }
        vm.stopPrank();
    }

    function test_slash_vault_with_zero_total_assets(uint96 slashPercentageWad) public {
        vm.assume(
            slashPercentageWad > Constants.ONE_WAD && slashPercentageWad <= core.getDssMaxSlashablePercentageWad(dss)
        );
        stake_vaults_to_dss();

        vm.prank(operator);
        core.registerOperatorToDSS(dss2, "");
        uint96[] memory slashPercentagesWad = new uint96[](vaults.length);
        slashPercentagesWad[0] = slashPercentageWad;
        // Generate nonequal percentages
        uint96 slashPercentageWad1 =
            (slashPercentageWad + uint96(10 * Constants.ONE_WAD)) % uint96(core.getDssMaxSlashablePercentageWad(dss));
        // Make sure zero is not passed
        slashPercentageWad1 = slashPercentageWad1 == 0 ? slashPercentageWad1 : uint96(Constants.ONE_WAD);
        slashPercentagesWad[1] = slashPercentageWad1;

        vm.startPrank(address(dss));
        address[] memory operatorVaults = core.fetchVaultsStakedInDSS(operator, dss);

        SlasherLib.SlashRequest memory slashingReq = SlasherLib.SlashRequest({
            operator: operator,
            slashPercentagesWad: slashPercentagesWad,
            vaults: operatorVaults
        });

        SlasherLib.QueuedSlashing memory queuedSlashing = core.requestSlashing(slashingReq);

        withdraw_all_shares(address(this), Vault(address(vaults[0])));
        vm.warp(block.timestamp + Constants.SLASHING_VETO_WINDOW);

        uint256[] memory postSlashedAssets = new uint256[](operatorVaults.length);
        for (uint256 i = 0; i < operatorVaults.length; i++) {
            postSlashedAssets[i] = compute_post_slashed_assets_in_vault(operatorVaults[i], slashPercentagesWad[i]);
        }

        core.finalizeSlashing(queuedSlashing);
        for (uint256 i = 0; i < operatorVaults.length; i++) {
            assertEq(IVault(operatorVaults[i]).totalAssets(), postSlashedAssets[i]);
        }
        vm.stopPrank();
    }

    function test_fail_slash_operator_unregistered_before_finalize_slashing(uint96 slashPercentageWad) public {
        vm.assume(
            slashPercentageWad > Constants.ONE_WAD && slashPercentageWad <= core.getDssMaxSlashablePercentageWad(dss)
        );
        stake_vaults_to_dss();

        vm.prank(operator);
        core.registerOperatorToDSS(dss2, "");
        uint96[] memory slashPercentagesWad = new uint96[](vaults.length);
        slashPercentagesWad[0] = slashPercentageWad;
        // Generate nonequal percentages
        uint96 slashPercentageWad1 =
            (slashPercentageWad + uint96(10 * Constants.ONE_WAD)) % uint96(core.getDssMaxSlashablePercentageWad(dss));
        // Make sure zero is not passed
        slashPercentageWad1 = slashPercentageWad1 == 0 ? slashPercentageWad1 : uint96(Constants.ONE_WAD);
        slashPercentagesWad[1] = slashPercentageWad1;

        vm.startPrank(address(dss));
        address[] memory operatorVaults = core.fetchVaultsStakedInDSS(operator, dss);

        SlasherLib.SlashRequest memory slashingReq = SlasherLib.SlashRequest({
            operator: operator,
            slashPercentagesWad: slashPercentagesWad,
            vaults: operatorVaults
        });

        SlasherLib.QueuedSlashing memory queuedSlashing = core.requestSlashing(slashingReq);

        for (uint256 i = 0; i < operatorVaults.length; i++) {
            update_vault_stake_to_dss(operatorVaults[i], false, dss);
        }

        vm.stopPrank();
        vm.prank(operator);
        core.unregisterOperatorFromDSS(dss);

        vm.warp(block.timestamp + Constants.SLASHING_VETO_WINDOW);

        vm.startPrank(address(dss));
        vm.expectRevert(OperatorNotValidatingForDSS.selector);
        core.finalizeSlashing(queuedSlashing);
        vm.stopPrank();
    }

    function test_slash_operator_operator_contract(uint96 slashPercentageWad) public {
        operator = address(operatorSC);
        test_slash_operator(slashPercentageWad);
    }

    function test_slash_operator_min_delay_not_passed(uint96 slashPercentageWad, uint256 delay) public {
        vm.assume(
            slashPercentageWad > Constants.ONE_WAD && slashPercentageWad <= core.getDssMaxSlashablePercentageWad(dss)
        );
        if (delay >= Constants.SLASHING_VETO_WINDOW) return;
        stake_vaults_to_dss();
        uint96[] memory slashPercentagesWad = new uint96[](vaults.length);
        slashPercentagesWad[0] = slashPercentageWad;
        // Generate nonequal percentages
        uint96 slashPercentageWad1 =
            (slashPercentageWad + uint96(10 * Constants.ONE_WAD)) % uint96(core.getDssMaxSlashablePercentageWad(dss));
        // Make sure zero is not passed
        slashPercentageWad1 = slashPercentageWad1 == 0 ? slashPercentageWad1 : uint96(Constants.ONE_WAD);
        slashPercentagesWad[1] = slashPercentageWad1;

        vm.startPrank(address(dss));
        (address[] memory operatorVaults) = core.fetchVaultsStakedInDSS(operator, dss);

        SlasherLib.SlashRequest memory slashingReq = SlasherLib.SlashRequest({
            operator: operator,
            slashPercentagesWad: slashPercentagesWad,
            vaults: operatorVaults
        });

        SlasherLib.QueuedSlashing memory queuedSlashing = core.requestSlashing(slashingReq);

        vm.warp(block.timestamp + delay);

        vm.expectRevert(MinSlashingDelayNotPassed.selector);
        core.finalizeSlashing(queuedSlashing);
        vm.stopPrank();
    }

    function test_finalize_slash_operator_invalid_params(uint96 slashPercentageWad, uint256 delay) public {
        vm.assume(
            slashPercentageWad > Constants.ONE_WAD && slashPercentageWad <= core.getDssMaxSlashablePercentageWad(dss)
        );
        vm.assume(delay > Constants.SLASHING_VETO_WINDOW && delay < UINT256_MAX / 2);
        stake_vaults_to_dss();
        uint96[] memory slashPercentagesWad = new uint96[](vaults.length);
        slashPercentagesWad[0] = slashPercentageWad;
        // Generate nonequal percentages
        uint96 slashPercentageWad1 =
            (slashPercentageWad + uint96(10 * Constants.ONE_WAD)) % uint96(core.getDssMaxSlashablePercentageWad(dss));
        // Make sure zero is not passed
        slashPercentageWad1 = slashPercentageWad1 == 0 ? slashPercentageWad1 : uint96(Constants.ONE_WAD);
        slashPercentagesWad[1] = slashPercentageWad1;

        vm.startPrank(address(dss));
        address[] memory operatorVaults = core.fetchVaultsStakedInDSS(operator, dss);

        SlasherLib.SlashRequest memory slashingReq = SlasherLib.SlashRequest({
            operator: operator,
            slashPercentagesWad: slashPercentagesWad,
            vaults: operatorVaults
        });

        SlasherLib.QueuedSlashing memory queuedSlashing = core.requestSlashing(slashingReq);
        queuedSlashing.nonce++;
        vm.warp(block.timestamp + delay);

        vm.expectRevert(InvalidSlashingParams.selector);
        core.finalizeSlashing(queuedSlashing);
        vm.stopPrank();
    }

    function test_cancel_slashing_operator(uint96 slashPercentageWad, uint256 elapsedTime) public {
        if (elapsedTime >= Constants.SLASHING_VETO_WINDOW) return;
        vm.assume(
            slashPercentageWad > Constants.ONE_WAD && slashPercentageWad <= core.getDssMaxSlashablePercentageWad(dss)
        );
        stake_vaults_to_dss();
        uint96[] memory slashPercentagesWad = new uint96[](vaults.length);
        slashPercentagesWad[0] = slashPercentageWad;
        // Generate nonequal percentages
        uint96 slashPercentageWad1 =
            (slashPercentageWad + uint96(10 * Constants.ONE_WAD)) % uint96(core.getDssMaxSlashablePercentageWad(dss));
        // Make sure zero is not passed
        slashPercentageWad1 = slashPercentageWad1 == 0 ? slashPercentageWad1 : uint96(Constants.ONE_WAD);
        slashPercentagesWad[1] = slashPercentageWad1;

        vm.startPrank(address(dss));
        address[] memory operatorVaults = core.fetchVaultsStakedInDSS(operator, dss);

        SlasherLib.SlashRequest memory slashingReq = SlasherLib.SlashRequest({
            operator: operator,
            slashPercentagesWad: slashPercentagesWad,
            vaults: operatorVaults
        });
        SlasherLib.QueuedSlashing memory queuedSlashing = core.requestSlashing(slashingReq);
        vm.stopPrank();

        vm.warp(block.timestamp + elapsedTime);
        vm.prank(vetoCommittee);
        core.cancelSlashing(queuedSlashing);
    }

    function test_fail_cancel_slashing_operator(uint96 slashPercentageWad, address caller, address newOperator)
        public
    {
        vm.assume(
            slashPercentageWad > Constants.ONE_WAD && slashPercentageWad <= core.getDssMaxSlashablePercentageWad(dss)
        );
        stake_vaults_to_dss();
        uint96[] memory slashPercentagesWad = new uint96[](vaults.length);
        slashPercentagesWad[0] = slashPercentageWad;
        // Generate nonequal percentages
        uint96 slashPercentageWad1 =
            (slashPercentageWad + uint96(10 * Constants.ONE_WAD)) % uint96(core.getDssMaxSlashablePercentageWad(dss));
        // Make sure zero is not passed
        slashPercentageWad1 = slashPercentageWad1 == 0 ? slashPercentageWad1 : uint96(Constants.ONE_WAD);
        slashPercentagesWad[1] = slashPercentageWad1;

        vm.startPrank(address(dss));
        address[] memory operatorVaults = core.fetchVaultsStakedInDSS(operator, dss);

        SlasherLib.SlashRequest memory slashingReq = SlasherLib.SlashRequest({
            operator: operator,
            slashPercentagesWad: slashPercentagesWad,
            vaults: operatorVaults
        });
        SlasherLib.QueuedSlashing memory queuedSlashing = core.requestSlashing(slashingReq);
        vm.stopPrank();

        // not veto committee
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(caller);
        core.cancelSlashing(queuedSlashing);

        // changed operator
        queuedSlashing.operator = newOperator;
        vm.expectRevert(InvalidSlashingParams.selector);
        vm.prank(vetoCommittee);
        core.cancelSlashing(queuedSlashing);
    }

    function test_slash_subset_of_operator_vaults(uint96 slashPercentageWad) public {
        vm.assume(
            slashPercentageWad > Constants.ONE_WAD && slashPercentageWad <= core.getDssMaxSlashablePercentageWad(dss)
        );
        stake_vaults_to_dss();
        uint96[] memory slashPercentagesWad = new uint96[](1);
        slashPercentagesWad[0] = uint96(slashPercentageWad);

        vm.startPrank(address(dss));
        address[] memory operatorVaults = core.fetchVaultsStakedInDSS(operator, dss);

        address[] memory slashedVaults = new address[](1);
        slashedVaults[0] = operatorVaults[0];

        SlasherLib.SlashRequest memory slashingReq = SlasherLib.SlashRequest({
            operator: operator,
            slashPercentagesWad: slashPercentagesWad,
            vaults: slashedVaults
        });

        SlasherLib.QueuedSlashing memory queuedSlashing = core.requestSlashing(slashingReq);

        vm.warp(block.timestamp + Constants.SLASHING_VETO_WINDOW);

        uint256[] memory postSlashedAssetsInVault = new uint256[](slashedVaults.length);
        for (uint256 i = 0; i < slashedVaults.length; i++) {
            postSlashedAssetsInVault[i] = compute_post_slashed_assets_in_vault(slashedVaults[i], slashPercentagesWad[i]);
        }

        core.finalizeSlashing(queuedSlashing);

        for (uint256 i = 0; i < slashedVaults.length; i++) {
            assertEq(IVault(operatorVaults[i]).totalAssets(), postSlashedAssetsInVault[i]);
        }

        vm.stopPrank();
    }

    function test_slash_subset_of_operator_vaults_operator_contract(uint96 slashPercentageWad) public {
        operator = address(operatorSC);
        test_slash_subset_of_operator_vaults(slashPercentageWad);
    }

    function test_invalid_slashing_request(uint96 slashPercentageWad) public {
        stake_vaults_to_dss();
        vm.assume(
            slashPercentageWad > Constants.ONE_WAD && slashPercentageWad <= core.getDssMaxSlashablePercentageWad(dss)
        );
        uint96[] memory slashPercentagesWad = new uint96[](vaults.length);
        slashPercentagesWad[0] = slashPercentageWad;
        // Generate nonequal percentages
        uint96 slashPercentageWad1 =
            (slashPercentageWad + uint96(10 * Constants.ONE_WAD)) % uint96(core.getDssMaxSlashablePercentageWad(dss));
        // Make sure zero is not passed
        slashPercentageWad1 = slashPercentageWad1 == 0 ? slashPercentageWad1 : uint96(Constants.ONE_WAD);
        slashPercentagesWad[1] = slashPercentageWad1;

        // Vault not staked in DSS
        address[] memory operatorVaults = core.fetchVaultsStakedInDSS(operator, dss);

        SlasherLib.SlashRequest memory slashingReq = SlasherLib.SlashRequest({
            operator: operator,
            slashPercentagesWad: slashPercentagesWad,
            vaults: operatorVaults
        });

        // not registered with core
        vm.expectRevert(DSSNotRegistered.selector);
        core.requestSlashing(slashingReq);

        // not registered with dss
        slashingReq.operator = operator;
        vm.expectRevert(OperatorNotValidatingForDSS.selector);
        vm.prank(address(dss2));
        core.requestSlashing(slashingReq);

        // request slashing before cooldown period
        vm.startPrank(address(dss));
        core.requestSlashing(slashingReq);
        vm.expectRevert(SlashingCooldownNotPassed.selector);
        core.requestSlashing(slashingReq);
        vm.stopPrank();

        vm.warp(block.timestamp + Constants.SLASHING_COOLDOWN);

        slashingReq.slashPercentagesWad[0] = uint96(Constants.MAX_SLASHING_PERCENT_WAD) + 100;
        vm.expectRevert(MaxSlashPercentageWadBreached.selector);
        vm.startPrank(address(dss));
        core.requestSlashing(slashingReq);
        vm.stopPrank();

        slashingReq.slashPercentagesWad[0] = slashPercentageWad;

        // Vault not staked by operator to DSS
        update_vault_stake_to_dss(operatorVaults[0], false, dss);
        vm.expectRevert(VaultNotStakedToDSS.selector);
        vm.startPrank(address(dss));
        core.requestSlashing(slashingReq);
        vm.stopPrank();

        // check for duplicate vaults
        slashingReq.vaults[1] = slashingReq.vaults[0];
        vm.expectRevert(DuplicateSlashingVaults.selector);
        vm.startPrank(address(dss));
        core.requestSlashing(slashingReq);
        vm.stopPrank();

        // slashingRequest.vaults.length == 0
        slashingReq.vaults = new address[](0);
        slashingReq.slashPercentagesWad = new uint96[](0);
        vm.expectRevert(EmptyArray.selector);
        vm.startPrank(address(dss));
        core.requestSlashing(slashingReq);
        vm.stopPrank();

        // slashingRequest.slashPercentagesWad.length != slashingRequest.vaults.length
        slashingReq.vaults = new address[](10);
        slashingReq.slashPercentagesWad = new uint96[](9);
        vm.expectRevert(LengthsDontMatch.selector);
        vm.startPrank(address(dss));
        core.requestSlashing(slashingReq);
        vm.stopPrank();

        // slashingRequest.vaults.length > Constants.MAX_SLASHABLE_VAULTS_PER_REQUEST
        slashingReq.vaults = new address[](Constants.MAX_SLASHABLE_VAULTS_PER_REQUEST + 1);
        slashingReq.slashPercentagesWad = new uint96[](Constants.MAX_SLASHABLE_VAULTS_PER_REQUEST + 1);
        vm.expectRevert(MaxSlashableVaultsPerRequestBreached.selector);
        vm.startPrank(address(dss));
        core.requestSlashing(slashingReq);
        vm.stopPrank();
    }

    function test_staker_withdraw_pre_and_post_slashing() public {
        stake_vaults_to_dss();
        address beneficiary1 = address(21);
        address beneficiary2 = address(22);
        uint256 withdrawAmt1 = 500;
        uint256 withdrawAmt2 = 400;
        uint256 slashPercentageWad = core.getDssMaxSlashablePercentageWad(dss);
        // initiate 2 withdrawals of 500 each
        // finish one before and one post slashing
        IERC20(address(vaults[0])).approve(address(vaults[0]), withdrawAmt1 + withdrawAmt2);
        bytes32 withdrawalKey1 = IVault(address(vaults[0])).startRedeem(withdrawAmt1, beneficiary1);
        bytes32 withdrawalKey2 = IVault(address(vaults[0])).startRedeem(withdrawAmt2, beneficiary2);

        vm.warp(block.timestamp + Constants.SLASHING_WINDOW);
        // queue a slashing
        address[] memory operatorVaults = core.fetchVaultsStakedInDSS(operator, dss);
        uint96[] memory slashPercentagesWad = new uint96[](vaults.length);
        slashPercentagesWad[0] = uint96(slashPercentageWad);
        slashPercentagesWad[1] = uint96(slashPercentageWad);
        vm.startPrank(address(dss));
        SlasherLib.SlashRequest memory slashingReq = SlasherLib.SlashRequest({
            operator: operator,
            slashPercentagesWad: slashPercentagesWad,
            vaults: operatorVaults
        });

        SlasherLib.QueuedSlashing memory queuedSlashing = core.requestSlashing(slashingReq);

        vm.warp(block.timestamp + Constants.SLASHING_VETO_WINDOW);
        // first withdraw gets a full withdrawal
        IVault(address(vaults[0])).finishRedeem(withdrawalKey1);
        assertEq(depositToken.balanceOf(beneficiary1), withdrawAmt1);

        core.finalizeSlashing(queuedSlashing);
        // second withdraw gets slashed withdrawal
        IVault(address(vaults[0])).finishRedeem(withdrawalKey2);
        assertEq(
            depositToken.balanceOf(beneficiary2),
            Math.mulDiv(
                withdrawAmt2, (Constants.HUNDRED_PERCENT_WAD - slashPercentageWad), Constants.HUNDRED_PERCENT_WAD
            )
        );
    }

    function _getNonce() internal view returns (uint256) {
        bytes32 slot = 0x13c729cff436dc8ac22d145f2c778f6a709d225083f39538cc5e2674f2f10700;
        uint256 nonceSlot = uint256(slot) + 7;
        uint256 result = uint256(vm.load(address(core), bytes32(nonceSlot)));
        uint256 ans = result >> 160;
        return ans;
    }

    function test_slash_operator_with_multiple_DSS(uint256 slashPercentage1, uint256 slashPercentage2) public {
        deposit_into_vaults();
        update_vault_stake_to_dss(address(vaults[0]), true, dss);
        update_vault_stake_to_dss(address(vaults[1]), true, dss);
        vm.prank(operator);
        core.registerOperatorToDSS(dss2, "");
        update_vault_stake_to_dss(address(vaults[0]), true, dss2);

        slashPercentage1 = slashPercentage1 % dssMaxSlashablePercentageWad + 1;
        slashPercentage2 = slashPercentage2 % dss2MaxSlashablePercentageWad + 1;

        address[] memory operatorVaultsDSS = core.fetchVaultsStakedInDSS(operator, dss);
        SlasherLib.SlashRequest memory slashingReq1 = _slashRequestObj(operator, slashPercentage1, operatorVaultsDSS);
        address[] memory operatorVaultsDSS2 = core.fetchVaultsStakedInDSS(operator, dss2);
        SlasherLib.SlashRequest memory slashingReq2 = _slashRequestObj(operator, slashPercentage2, operatorVaultsDSS2);

        // stake more vaults
        update_vault_stake_to_dss(address(vaults[1]), true, dss2);

        vm.prank(address(dss));
        SlasherLib.QueuedSlashing memory queuedSlashing1 = core.requestSlashing(slashingReq1);
        vm.prank(address(dss2));
        SlasherLib.QueuedSlashing memory queuedSlashing2 = core.requestSlashing(slashingReq2);

        assertEq(_queuedSlashingCount(operator, slashingReq1.vaults[0]), 2);
        assertEq(_queuedSlashingCount(operator, slashingReq1.vaults[1]), 1);
        for (uint256 i = 0; i < slashingReq1.vaults.length; i++) {
            assertTrue(core.isVaultQueuedForSlashing(slashingReq1.vaults[i]));
        }

        vm.warp(block.timestamp + Constants.SLASHING_COOLDOWN);
        vm.prank(address(dss));
        core.finalizeSlashing(queuedSlashing1);

        assertEq(_queuedSlashingCount(operator, address(vaults[0])), 1);
        assertEq(_queuedSlashingCount(operator, address(vaults[1])), 0);
        assertTrue(core.isVaultQueuedForSlashing(slashingReq1.vaults[0]));
        assertFalse(core.isVaultQueuedForSlashing(slashingReq1.vaults[1]));

        vm.prank(address(dss2));
        core.finalizeSlashing(queuedSlashing2);
        assertEq(_queuedSlashingCount(operator, address(vaults[0])), 0);
        assertEq(_queuedSlashingCount(operator, address(vaults[1])), 0);
        assertFalse(core.isVaultQueuedForSlashing(slashingReq1.vaults[0]));
        assertFalse(core.isVaultQueuedForSlashing(slashingReq1.vaults[1]));
    }

    function test_cancel_slash_operator_with_multiple_DSS(uint256 slashPercentage1, uint256 slashPercentage2) public {
        deposit_into_vaults();
        update_vault_stake_to_dss(address(vaults[0]), true, dss);
        vm.prank(operator);
        core.registerOperatorToDSS(dss2, "");
        update_vault_stake_to_dss(address(vaults[0]), true, dss2);

        slashPercentage1 = slashPercentage1 % dssMaxSlashablePercentageWad + 1;
        slashPercentage2 = slashPercentage2 % dss2MaxSlashablePercentageWad + 1;

        address[] memory operatorVaultsDSS = core.fetchVaultsStakedInDSS(operator, dss);
        SlasherLib.SlashRequest memory slashingReq1 = _slashRequestObj(operator, slashPercentage1, operatorVaultsDSS);
        address[] memory operatorVaultsDSS2 = core.fetchVaultsStakedInDSS(operator, dss2);
        SlasherLib.SlashRequest memory slashingReq2 = _slashRequestObj(operator, slashPercentage2, operatorVaultsDSS2);

        // stake more vaults
        update_vault_stake_to_dss(address(vaults[1]), true, dss);
        update_vault_stake_to_dss(address(vaults[1]), true, dss2);

        vm.prank(address(dss));
        SlasherLib.QueuedSlashing memory queuedSlashing1 = core.requestSlashing(slashingReq1);
        vm.prank(address(dss2));
        SlasherLib.QueuedSlashing memory queuedSlashing2 = core.requestSlashing(slashingReq2);

        assertEq(_queuedSlashingCount(operator, slashingReq1.vaults[0]), 2);
        assertTrue(core.isVaultQueuedForSlashing(slashingReq1.vaults[0]));

        vm.warp(block.timestamp + Constants.SLASHING_COOLDOWN);
        vm.prank(vetoCommittee);
        core.cancelSlashing(queuedSlashing1);

        assertEq(_queuedSlashingCount(operator, slashingReq1.vaults[0]), 1);
        assertTrue(core.isVaultQueuedForSlashing(slashingReq1.vaults[0]));

        vm.prank(vetoCommittee);
        core.cancelSlashing(queuedSlashing2);
        assertEq(_queuedSlashingCount(operator, slashingReq1.vaults[0]), 0);
        assertFalse(core.isVaultQueuedForSlashing(slashingReq1.vaults[0]));
    }

    function _slashRequestObj(address operator, uint256 slashPercentage, address[] memory vaults)
        internal
        pure
        returns (SlasherLib.SlashRequest memory)
    {
        uint96[] memory vaultSlashPercentages = new uint96[](vaults.length);
        for (uint256 i = 0; i < vaultSlashPercentages.length; i++) {
            vaultSlashPercentages[i] = uint96(slashPercentage);
        }
        return SlasherLib.SlashRequest({operator: operator, slashPercentagesWad: vaultSlashPercentages, vaults: vaults});
    }

    function _queuedSlashingCount(address currOperator, address currrVault) internal view returns (uint256) {
        bytes32 queuedSlashingCountSlot = CoreStorageSlots.vaultQueuedSlashingSlot(currOperator, currrVault);
        bytes32 result = vm.load(address(core), queuedSlashingCountSlot);
        return uint256(result);
    }
}
