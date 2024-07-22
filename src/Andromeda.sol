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
    address public constant SHA512_ADDR = 0x0000000000000000000000000000000000050700;
    address public constant DO_HTTP_REQUEST = 0x0000000000000000000000000000000043200002;
    address public constant X509_GENERATE_ADDR = 0x0000000000000000000000000000000000070700;

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
        bytes memory userReport = abi.encodePacked(sha256(userdata), uint256(0));
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
        (bool success, bytes memory sealingBytes) = SEALINGKEY_ADDR.staticcall("");
        require(success);
        require(sealingBytes.length == 32);
        return bytes32(keccak256(abi.encode(bytes32(sealingBytes), key)));
    }

    function sha512(bytes memory data) external view override returns (bytes memory) {
        require(data.length > 0, "sha512: data length must be greater than 0");
        (bool success, bytes memory output) = SHA512_ADDR.staticcall(data);
        require(success);
        require(output.length == 64);
        return output;
    }

    function doHTTPRequest(IAndromeda.HttpRequest memory request) external returns (bytes memory) {
        (bool success, bytes memory data) = DO_HTTP_REQUEST.call(abi.encode(request));
        require(success);
        return abi.decode(data, (bytes));
    }

    function x509Generate(bytes calldata skPkcs8Der, string calldata domain, string calldata subject)
        external
        view
        returns (bytes memory)
    {
        (bool success, bytes memory data) = X509_GENERATE_ADDR.staticcall(abi.encode(skPkcs8Der, domain, subject));
        require(success);
        return abi.decode(data, (bytes));
    }
}
