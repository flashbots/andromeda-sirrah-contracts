// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import "solidity-stringutils/strings.sol";

//import "forge-std/Vm.sol";
import "forge-std/StdJson.sol";
import "forge-std/console2.sol";

import {IAndromeda} from "src/IAndromeda.sol";
import {SigVerifyLib} from "automata-dcap-v3-attestation/utils/SigVerifyLib.sol";
import {DcapDemo} from "src/DcapVerifier.sol";
import {EnclaveIdStruct, TCBInfoStruct} from "automata-dcap-v3-attestation/AutomataDcapV3Attestation.sol";
import {V3Struct} from "automata-dcap-v3-attestation/lib/QuoteV3Auth/V3Struct.sol";
import {V3Parser} from "automata-dcap-v3-attestation/lib/QuoteV3Auth/V3Parser.sol";

interface Vm {
    function warp(uint) external view;
    function ffi(string[] calldata commandInput) external view returns (bytes memory result);
    function setEnv(string calldata name, string calldata value) external;
    function envOr(string calldata key, bytes32 defaultValue) external returns (bytes32 value);
    function readFile(string calldata path) external view returns (string memory data);
    function prank(address caller) external;
    function parseJson(string memory json, string memory key) external view;
    function parseBytes(string memory b) external view returns (bytes memory);
    function projectRoot() external view returns (string memory);
}

contract AndromedaRemote is IAndromeda, DcapDemo {
    using strings for *;
    using stdJson for string;

    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    constructor(address sigVerifyLib) DcapDemo(sigVerifyLib) {}

    function initialize() public {
        // This is the dummy enclave from the service
        // https://github.com/amiller/gramine-dummy-attester/tree/dcap
	setMrSigner(bytes32(0x1cf2e52911410fbf3f199056a98d58795a559a2e800933f7fcd13d048462271c), true);
        setMrEnclave(bytes32(0xed24ce78cd65438dc3b74e549b1ad5c591dba88e2078e676fca600ebbec21370), true);

        // Set the timestamp (to avoid certificate expiry check);
        vm.warp(1718132125);

        // By setting the report check, we now have to check mrsigner
        // AND mrenclave. Even though this is a little redundant!
        // We should modify upstream for this.
        // In the meantime we can make it easy to set mrsigner trusted
        //toggleLocalReportCheck();

        // Load Quoting Enclave identity (part of the tcb, signed by intel)
        {
            string memory p = "test/fixtures/quotingenclave-identity.json";
            EnclaveIdStruct.EnclaveId memory s = parseIdentity(p);
            vm.prank(address(owner));
            this.configureQeIdentityJson(s);
        }
        // Load one of the TCB Infos. These are signed by Intel. But here the signature isn't checked. FIXME
        {
            TCBInfoStruct.TCBInfo memory s = parseTcbInfo("test/fixtures/tcbInfo.json");
            vm.prank(address(owner));
            this.configureTcbInfoJson(s.fmspc, s);
        }
        {
            TCBInfoStruct.TCBInfo memory s = parseTcbInfo("test/fixtures/tcbInfo2.json");
            vm.prank(address(owner));
            this.configureTcbInfoJson(s.fmspc, s);
        }
    }

    function attestSgx(bytes32 appData) public view returns (bytes memory) {
	console2.log("attestSgx remote");
        bytes memory userdata = abi.encode(address(this), abi.encodePacked(msg.sender, appData));
	console2.logBytes(userdata);
	bytes memory userReport = abi.encodePacked(sha256(userdata), uint(0));
        string[] memory inputs = new string[](3);
        inputs[0] = "python";
        inputs[1] = "ffi/ffi-fetchquote-dcap.py";
        inputs[2] = iToHex(abi.encodePacked(userReport));
        bytes memory res = vm.ffi(inputs);
        return res;
    }

    function verifySgx(address caller, bytes32 appData, bytes memory att) public view returns (bool) {
	console2.log("verifySgx remote");
	//console2.logBytes(att);
        bytes memory userdata = abi.encode(address(this), abi.encodePacked(caller, appData));
	bytes memory userReport = abi.encodePacked(sha256(userdata), uint(0));
        (,, V3Struct.EnclaveReport memory r,,) = V3Parser.parseInput(att);
        if (keccak256(r.reportData) != keccak256(userReport)) {
            return false;
        }
        return this.verifyAttestation(att);
    }


    function verifyTDXDCAPQuote(bytes memory quote, string memory pckCertPem, string memory pckCrlPem, string memory tcbInfoJson, string memory qeIdentityJson) external view override returns (uint) {
        return uint(0);
    }

    function localRandom() public view returns (bytes32) {
        string[] memory inputs = new string[](2);
        inputs[0] = "sh";
        inputs[1] = "ffi/local_random.sh";
        bytes memory res = vm.ffi(inputs);
        return bytes32(res);
    }

    function sealingKey(bytes32 tag) public view returns (bytes32) {
        bytes32 salt = hex"234902409284092384092384";
        // Make a fake sealing key just using a salt
        return bytes32(keccak256(abi.encode(activeHost, salt, msg.sender, tag)));
    }

    function toEnv(string memory host, address caller, bytes32 tag) internal pure returns (string memory) {
        strings.slice memory m = "SUAVE_VOLATILE_".toSlice().concat(iToHex(abi.encodePacked(caller)).toSlice()).toSlice(
        ).concat("_".toSlice()).toSlice();
        return m.concat(host.toSlice()).toSlice().concat("_".toSlice()).toSlice().concat(
            iToHex(abi.encodePacked(tag)).toSlice()
        );
    }

    function volatileSet(bytes32 tag, bytes32 value) public {
        address caller = msg.sender;
        string memory env = toEnv(activeHost, caller, tag);
        vm.setEnv(env, iToHex(abi.encodePacked(value)));
    }

    function volatileGet(bytes32 tag) public returns (bytes32) {
        address caller = msg.sender;
        string memory env = toEnv(activeHost, caller, tag);
        return vm.envOr(env, bytes32(""));
    }

    function doHTTPRequest(IAndromeda.HttpRequest memory) external pure returns (bytes memory) {
        return bytes("");
    }

    // Currently active host
    string activeHost = "default";

    function switchHost(string memory host) public {
        activeHost = host;
    }

    function iToHex(bytes memory buffer) public pure returns (string memory) {
        bytes memory converted = new bytes(buffer.length * 2);
        bytes memory _base = "0123456789abcdef";
        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }
        return string(converted);
        //return string(abi.encodePacked("0x", converted));
    }

    function sha512(bytes memory data) external view override returns (bytes memory) {
        require(data.length > 0, "sha512: data length must be greater than 0");
        string[] memory inputs = new string[](3);
        inputs[0] = "sh";
        inputs[1] = "ffi/sha512.sh";
        inputs[2] = string(data);
        return vm.ffi(inputs);
    }

    ///////////////////////////////////////////////////////
    // Forge functions for tcbInfo and qeIdentity from file
    ///////////////////////////////////////////////////////

    struct EnclaveId {
        bytes attributes;
        bytes attributesMask;
        uint16 isvprodid;
        bytes miscselect;
        bytes miscselectMask;
        bytes mrsigner;
        TcbLevel[] tcbLevels;
    }

    struct TcbLevel {
        EnclaveIdStruct.TcbObj tcb;
        string tcbStatus;
    }

    struct TCBInfo {
        string fmspc;
        string pceid;
        TCBLevelObj[] tcbLevels;
    }

    struct TCBLevelObj {
        uint256 pcesvn;
        uint256[] sgxTcbCompSvnArr;
        TCBInfoStruct.TCBStatus status;
    }

    function parseIdentity(string memory path) public view returns (EnclaveIdStruct.EnclaveId memory r) {
        string memory json = vm.readFile(path);
        bytes memory enclaveId = json.parseRaw(".enclaveIdentity");
        EnclaveId memory t = abi.decode(enclaveId, (EnclaveId));
        r.miscselect = bytes4(vm.parseBytes(string(t.miscselect)));
        r.miscselectMask = bytes4(vm.parseBytes(string(t.miscselectMask)));
        r.isvprodid = t.isvprodid;
        r.attributes = bytes16(vm.parseBytes(string(t.attributes)));
        r.attributesMask = bytes16(vm.parseBytes(string(t.attributesMask)));
        r.mrsigner = bytes32(vm.parseBytes(string(t.mrsigner)));
        r.tcbLevels = new EnclaveIdStruct.TcbLevel[](t.tcbLevels.length);
        for (uint256 i = 0; i < t.tcbLevels.length; i++) {
            r.tcbLevels[i].tcb = t.tcbLevels[i].tcb;
            if (t.tcbLevels[i].tcbStatus.toSlice().equals("UpToDate".toSlice())) {
                r.tcbLevels[i].tcbStatus = EnclaveIdStruct.EnclaveIdStatus.OK;
            } else {
                r.tcbLevels[i].tcbStatus = EnclaveIdStruct.EnclaveIdStatus.SGX_ENCLAVE_REPORT_ISVSVN_REVOKED;
            }
        }
    }

    function parseTcbInfo(string memory path) public view returns (TCBInfoStruct.TCBInfo memory) {
        string memory json = vm.readFile(path);
        bytes memory tcbInfo = json.parseRaw(".");
	//console2.logBytes(tcbInfo);
        TCBInfo memory t = abi.decode(tcbInfo, (TCBInfo));
        TCBInfoStruct.TCBInfo memory r;
        r.fmspc = t.fmspc;
        r.pceid = t.pceid;
        r.tcbLevels = new TCBInfoStruct.TCBLevelObj[](t.tcbLevels.length);
        for (uint256 i = 0; i < t.tcbLevels.length; i++) {
            r.tcbLevels[i].pcesvn = t.tcbLevels[i].pcesvn;
            r.tcbLevels[i].status = t.tcbLevels[i].status;
            r.tcbLevels[i].sgxTcbCompSvnArr = t.tcbLevels[i].sgxTcbCompSvnArr;
        }
        return r;
    }
}
