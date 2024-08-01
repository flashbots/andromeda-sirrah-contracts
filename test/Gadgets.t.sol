pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {BIP32} from "../src/BIP32.sol";
import {AndromedaForge} from "src/AndromedaForge.sol";

import {AttestationGadget} from "src/gadgets/AttestationGadget.sol";

contract AttestationTestContract is AttestationGadget {
    AndromedaForge public andromeda;

    constructor(AndromedaForge _andromeda) {
        andromeda = _andromeda;
    }

    function offchain_attest(bytes32 user_data) internal virtual override returns (bytes memory attestation) {
        attestation = andromeda.attestSgx(user_data);
    }

    function onchain_verify_attestation(bytes32 user_data, bytes memory attestation)
        internal
        virtual
        override
        returns (bool)
    {
        return andromeda.verifySgx(address(this), user_data, attestation);
    }

    function offchain(bytes memory input_data) public returns (bytes memory attestation) {
        return offchain_attest(this.onchain.selector, input_data);
    }

    function onchain(bytes memory input_data, bytes memory attestation)
        public
        onchain_verify(input_data, attestation)
        returns (bytes memory)
    {
        return input_data;
    }
}

contract AttestationGadget_Test is Test {
    AndromedaForge public andromeda;
    AttestationTestContract testContract;

    function setUp() public {
        andromeda = new AndromedaForge();
        testContract = new AttestationTestContract(andromeda);
    }

    bytes32 constant salt = hex"234902409284092384092384";

    function testAttestationHappyPath() public {
        /* generate an offchain attestation */
        bytes memory attestation = testContract.offchain("xoxo");

        bytes memory expectedAppData =
            abi.encodePacked(AttestationTestContract.onchain.selector, address(testContract), "xoxo");
        bytes memory expectedAttestation =
            abi.encodePacked(keccak256(abi.encode(salt, address(testContract), keccak256(expectedAppData))));
        require(keccak256(attestation) == keccak256(expectedAttestation));

        /* verify the contract accepts the attestation */
        testContract.onchain("xoxo", attestation);
    }

    function testIncorrectAttestation() public {
        bytes memory attestation = testContract.offchain("xoxo");
        /* verify the contract does not accept an incorrect attestation */
        vm.expectRevert(bytes(""));
        testContract.onchain("xoxo", abi.encodePacked(keccak256(attestation)));
    }

    function testIncorrectCalldataForAttestation() public {
        bytes memory attestation = testContract.offchain("xoxo");
        /* verify the contract does not accept an attestation for different user data */
        vm.expectRevert(bytes(""));
        testContract.onchain("xoxo2", attestation);
    }
}
