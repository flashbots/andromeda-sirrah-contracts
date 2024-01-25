// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import "solidity-stringutils/strings.sol";
//import { Base64 } from "openzeppelin/utils/Base64.sol";
//import { BytesUtils } from "ens-contracts/dnssec-oracle/BytesUtils.sol";

import {
    AutomataDcapV3Attestation,
    TCBInfoStruct,
    ISigVerifyLib
} from "automata-dcap-v3-attestation/AutomataDcapV3Attestation.sol";

import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "forge-std/StdJson.sol";

contract DcapDemo is AutomataDcapV3Attestation {
    constructor(address sigVerifyLib) AutomataDcapV3Attestation(sigVerifyLib) {
        toggleLocalReportCheck();
    }

    function _attestationTcbIsValid(TCBInfoStruct.TCBStatus status) internal pure override returns (bool valid) {
        // Let's be very permissive!
        return (
            status == TCBInfoStruct.TCBStatus.OK || status == TCBInfoStruct.TCBStatus.TCB_SW_HARDENING_NEEDED
                || status == TCBInfoStruct.TCBStatus.TCB_CONFIGURATION_AND_SW_HARDENING_NEEDED
                || status == TCBInfoStruct.TCBStatus.TCB_CONFIGURATION_NEEDED
                || status == TCBInfoStruct.TCBStatus.TCB_OUT_OF_DATE
                || status == TCBInfoStruct.TCBStatus.TCB_OUT_OF_DATE_CONFIGURATION_NEEDED
                || status == TCBInfoStruct.TCBStatus.TCB_REVOKED
        );
    }
}
