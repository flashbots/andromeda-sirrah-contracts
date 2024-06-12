// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import "solidity-stringutils/strings.sol";
import {BytesUtils} from "ens-contracts/dnssec-oracle/BytesUtils.sol";

import "forge-std/console2.sol";
import "forge-std/Test.sol";

import {DcapDemo} from "src/DcapVerifier.sol";
import {EnclaveIdStruct, TCBInfoStruct} from "automata-dcap-v3-attestation/AutomataDcapV3Attestation.sol";
import {SigVerifyLib} from "automata-dcap-v3-attestation/utils/SigVerifyLib.sol";

import {AndromedaRemote} from "src/AndromedaRemote.sol";

contract DcapVerifyTest is Test {
    using stdJson for string;

    using strings for *;
    using BytesUtils for *;

    AndromedaRemote public andromeda;

    function setUp() public {
        SigVerifyLib lib = new SigVerifyLib();
        andromeda = new AndromedaRemote(address(lib));
        andromeda.initialize();
    }

    function testDecode() public {
        EnclaveIdStruct.EnclaveId memory s;
        andromeda.configureQeIdentityJson(s);
    }

    function testVerify() public {
	// For the included test quote
        andromeda.setMrEnclave(bytes32(0x185237a9e29c9c47ea060b3740a285ce2e36a0b7b11e049488f4c0c77329a7a0), true);
    
        // Set the timestamp (to avoid certificate expiry check);
        vm.warp(1701528486);
	
        // Test a pre-recorded attestation
        string memory s = vm.readFile("test/fixtures/testquote.hex");
        bytes memory quote = vm.parseBytes(s);
        assert(andromeda.verifyAttestation(quote));
    }

    function testRemote() public {
        // Use the FFI interface to verify a fresh quote
        bytes32 appData = keccak256("test hi");
        bytes memory quote = andromeda.attestSgx(appData);
        assert(andromeda.verifyAttestation(quote));
        assert(andromeda.verifySgx(address(this), appData, quote));
        assertFalse(andromeda.verifySgx(address(this), keccak256("no"), quote));
    }
}
