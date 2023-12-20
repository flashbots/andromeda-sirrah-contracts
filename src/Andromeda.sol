// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {IAndromeda} from "src/IAndromeda.sol";
import {DcapDemo} from "src/DcapVerifier.sol";
import {V3Struct} from "automata-dcap-v3-attestation/lib/QuoteV3Auth/V3Struct.sol";
import {V3Parser} from "automata-dcap-v3-attestation/lib/QuoteV3Auth/V3Parser.sol";

contract Andromeda is IAndromeda, DcapDemo {
    constructor(address sigVerifyLib) DcapDemo(sigVerifyLib) {}

    address public constant ATTEST_ADDR = 0x0000000000000000000000000000000000040700;
    address public constant VOLATILESET_ADDR = 0x0000000000000000000000000000000000040701;
    address public constant VOLATILEGET_ADDR = 0x0000000000000000000000000000000000040702;
    address public constant RANDOM_ADDR = 0x0000000000000000000000000000000000040703;
    address public constant SEALINGKEY_ADDR = 0x0000000000000000000000000000000000040704;

    function volatileSet(bytes32 key, bytes32 value) external override {
        bytes memory cdata = abi.encodePacked([key, value]);
        (bool success, bytes memory _out) = VOLATILESET_ADDR.staticcall(cdata);
        _out;
        require(success);
    }

    function volatileGet(bytes32 key) external override returns (bytes32) {
        (bool success, bytes memory value) = VOLATILEGET_ADDR.staticcall(abi.encodePacked((key)));
        require(success);
        require(value.length == 32);
        return abi.decode(value, (bytes32));
    }

    function attestSgx(bytes32 appData) external override returns (bytes memory) {
        (bool success, bytes memory attestBytes) = ATTEST_ADDR.staticcall(abi.encodePacked(msg.sender, appData));
        require(success);
        return attestBytes;
    }

    function verifySgx(address caller, bytes32 appData, bytes memory att) public view returns (bool) {
        bytes memory userdata = abi.encode(address(this), abi.encodePacked(caller, appData));
	bytes memory userReport = abi.encodePacked(sha256(userdata), uint(0));
        (,, V3Struct.EnclaveReport memory r,,) = V3Parser.parseInput(att);
        if (keccak256(r.reportData) != keccak256(userReport)) {
            return false;
        }
        return this.verifyAttestation(att);
    }

    function localRandom() external view override returns (bytes32) {
        (bool success, bytes memory randomBytes) = RANDOM_ADDR.staticcall("");
        require(success);
        require(randomBytes.length == 32);
        return bytes32(randomBytes);
    }

    function sealingKey(bytes32 key) external view returns (bytes32) {
        (bool success, bytes memory sealingBytes) = SEALINGKEY_ADDR.staticcall(abi.encodePacked((key)));
        require(success);
        require(sealingBytes.length == 32);
        return bytes32(sealingBytes);
    }
}
