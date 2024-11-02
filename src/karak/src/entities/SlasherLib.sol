// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {CoreLib} from "./CoreLib.sol";
import {HookLib} from "./HookLib.sol";
import {Operator} from "./Operator.sol";
import {CommonUtils} from "../utils/CommonUtils.sol";

import "../interfaces/Errors.sol";
import "../interfaces/Constants.sol";
import "../interfaces/IDSS.sol";
import "../interfaces/IKarakBaseVault.sol";
import "../interfaces/Events.sol";

library SlasherLib {
    using Operator for Operator.State;
    using Operator for CoreLib.Storage;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using CommonUtils for address[];

    struct SlashRequest {
        address operator;
        uint96[] slashPercentagesWad;
        address[] vaults;
    }

    struct QueuedSlashing {
        IDSS dss;
        uint96 timestamp;
        address operator;
        address[] vaults;
        uint96[] slashPercentagesWad;
        uint256 nonce;
    }

    function calculateRoot(QueuedSlashing memory queuedSlashing) internal pure returns (bytes32 root) {
        root = keccak256(abi.encode(queuedSlashing));
    }

    function validateVaultsAndSlashPercentages(
        CoreLib.Storage storage self,
        SlashRequest memory slashingRequest,
        IDSS dss
    ) internal view {
        if (slashingRequest.vaults.hasDuplicates()) revert DuplicateSlashingVaults();

        uint256 maxSlashPercentageWad = getDSSMaxSlashablePercentageWad(self, dss);
        for (uint256 i = 0; i < slashingRequest.vaults.length; i++) {
            if (!self.operatorState[slashingRequest.operator].isVaultStakedToDSS(dss, slashingRequest.vaults[i])) {
                revert VaultNotStakedToDSS();
            }
            if (slashingRequest.slashPercentagesWad[i] == 0) revert ZeroSlashPercentageWad();
            if (slashingRequest.slashPercentagesWad[i] > maxSlashPercentageWad) revert MaxSlashPercentageWadBreached();
        }
    }

    function validateRequestSlashingParams(CoreLib.Storage storage self, SlashRequest memory slashingRequest, IDSS dss)
        internal
        view
    {
        // revert if slashing cooldown has not passed
        if (block.timestamp < self.operatorState[slashingRequest.operator].nextSlashableTimestamp[dss]) {
            revert SlashingCooldownNotPassed();
        }
        // vaults length and corresponding slashPercentages array length should match
        if (slashingRequest.slashPercentagesWad.length != slashingRequest.vaults.length) revert LengthsDontMatch();
        // Max vaults slashed per request
        if (slashingRequest.vaults.length > Constants.MAX_SLASHABLE_VAULTS_PER_REQUEST) {
            revert MaxSlashableVaultsPerRequestBreached();
        }
        // Non zero vault length check
        if (slashingRequest.vaults.length == 0) revert EmptyArray();
        // Validate vault addresses and slashPercentages Values
        validateVaultsAndSlashPercentages(self, slashingRequest, dss);
    }

    function computeSlashAmount(address vault, uint256 slashPercentageWad) internal view returns (uint256) {
        return Math.mulDiv(slashPercentageWad, IKarakBaseVault(vault).totalAssets(), Constants.MAX_SLASHING_PERCENT_WAD);
    }

    function requestSlashing(
        CoreLib.Storage storage self,
        IDSS dss,
        SlashRequest memory slashingMetadata,
        uint256 nonce
    ) internal returns (QueuedSlashing memory queuedSlashing) {
        validateRequestSlashingParams(self, slashingMetadata, dss);
        queuedSlashing = QueuedSlashing({
            dss: dss,
            timestamp: uint96(block.timestamp),
            operator: slashingMetadata.operator,
            vaults: slashingMetadata.vaults,
            slashPercentagesWad: slashingMetadata.slashPercentagesWad,
            nonce: nonce
        });
        self.adjustQueuedSlashingCount(slashingMetadata.vaults, true);
        self.slashingRequests[calculateRoot(queuedSlashing)] = true;
        self.operatorState[slashingMetadata.operator].nextSlashableTimestamp[dss] =
            block.timestamp + Constants.SLASHING_COOLDOWN;
        HookLib.callHookIfInterfaceImplemented({
            dss: dss,
            data: abi.encodeWithSelector(
                dss.requestSlashingHook.selector, slashingMetadata.operator, slashingMetadata.slashPercentagesWad
            ),
            interfaceId: dss.requestSlashingHook.selector,
            ignoreFailure: true,
            hookCallGasLimit: self.hookCallGasLimit,
            supportsInterfaceGasLimit: self.supportsInterfaceGasLimit,
            hookGasBuffer: self.hookGasBuffer
        });
    }

    function finalizeSlashing(CoreLib.Storage storage self, QueuedSlashing memory queuedSlashing) internal {
        bytes32 slashRoot = calculateRoot(queuedSlashing);
        if (!self.slashingRequests[slashRoot]) revert InvalidSlashingParams();
        if (queuedSlashing.timestamp + Constants.SLASHING_VETO_WINDOW > block.timestamp) {
            revert MinSlashingDelayNotPassed();
        }
        delete self.slashingRequests[slashRoot];
        self.adjustQueuedSlashingCount(queuedSlashing.vaults, false);
        for (uint256 i = 0; i < queuedSlashing.vaults.length; i++) {
            if (
                !self.operatorState[queuedSlashing.operator].isVaultStakedToDSS(
                    queuedSlashing.dss, queuedSlashing.vaults[i]
                )
            ) {
                emit SkippedSlashing(queuedSlashing.vaults[i]);
                continue;
            }
            uint256 slashAmount = computeSlashAmount(queuedSlashing.vaults[i], queuedSlashing.slashPercentagesWad[i]);
            IKarakBaseVault(queuedSlashing.vaults[i]).slashAssets(
                slashAmount, self.assetSlashingHandlers[IKarakBaseVault(queuedSlashing.vaults[i]).asset()]
            );
        }

        IDSS dss = queuedSlashing.dss;

        HookLib.callHookIfInterfaceImplemented({
            dss: dss,
            data: abi.encodeWithSelector(dss.finishSlashingHook.selector, queuedSlashing.operator),
            interfaceId: dss.finishSlashingHook.selector,
            ignoreFailure: true,
            hookCallGasLimit: self.hookCallGasLimit,
            supportsInterfaceGasLimit: self.supportsInterfaceGasLimit,
            hookGasBuffer: self.hookGasBuffer
        });
    }

    function cancelSlashing(CoreLib.Storage storage self, QueuedSlashing memory queuedSlashing) internal {
        bytes32 slashRoot = calculateRoot(queuedSlashing);
        if (!self.slashingRequests[slashRoot]) revert InvalidSlashingParams();
        delete self.slashingRequests[slashRoot];
        self.adjustQueuedSlashingCount(queuedSlashing.vaults, false);
        IDSS dss = queuedSlashing.dss;

        HookLib.callHookIfInterfaceImplemented({
            dss: dss,
            data: abi.encodeWithSelector(dss.cancelSlashingHook.selector, queuedSlashing.operator),
            interfaceId: dss.cancelSlashingHook.selector,
            ignoreFailure: true,
            hookCallGasLimit: self.hookCallGasLimit,
            supportsInterfaceGasLimit: self.supportsInterfaceGasLimit,
            hookGasBuffer: self.hookGasBuffer
        });
    }

    function getDSSMaxSlashablePercentageWad(CoreLib.Storage storage self, IDSS dss) internal view returns (uint256) {
        return self.dssMaxSlashablePercentageWad[dss];
    }

    function setDSSMaxSlashablePercentageWad(
        CoreLib.Storage storage self,
        IDSS dss,
        uint256 dssMaxSlashablePercentageWad
    ) internal {
        uint256 currentSlashablePercentageWad = self.dssMaxSlashablePercentageWad[dss];
        if (currentSlashablePercentageWad != 0) revert DSSAlreadyRegistered();
        if (dssMaxSlashablePercentageWad == 0) revert ZeroSlashPercentageWad();
        if (dssMaxSlashablePercentageWad > Constants.MAX_SLASHING_PERCENT_WAD) revert MaxSlashPercentageWadBreached();
        self.dssMaxSlashablePercentageWad[dss] = dssMaxSlashablePercentageWad;
    }
}
