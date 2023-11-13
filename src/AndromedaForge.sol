// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;
import "solidity-stringutils/strings.sol";

interface Vm {
    function ffi(string[] calldata commandInput) external view returns (bytes memory result);
    function setEnv(string calldata name, string calldata value) external;
    function envOr(string calldata key, bytes32 defaultValue) external returns (bytes32 value);
}

contract AndromedaForge {
    using strings for *;

    bytes32 constant salt = hex"234902409284092384092384";

    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);    

    function attestSgx(bytes32 tag, bytes32 msghash) public view returns (bytes memory) {
	// Make a fake attestation just using a salt
	bytes32 hash = keccak256(abi.encode(salt, msg.sender, tag, msghash));
	return abi.encodePacked(hash);
    }

    function verifySgx(address caller, bytes32 tag, bytes32 msghash, bytes memory att) public pure {
	// Recreate the fake attestation
	bytes32 hash = keccak256(abi.encode(salt, caller, tag, msghash));
	require(hash == abi.decode(att, (bytes32)));
    }

    function localRandom() public view returns(bytes32) {
        string[] memory inputs = new string[](2);
        inputs[0] = "python";
        inputs[1] = "ffi/local_random.py";
        bytes memory res = vm.ffi(inputs);
	return bytes32(res);
    }

    function toEnv(string memory host, address caller, bytes32 tag) pure internal returns(string memory) {
	strings.slice memory m = "SUAVE_VOLATILE_".toSlice()	
	    .concat(iToHex(abi.encodePacked(caller)).toSlice()).toSlice()
	    .concat("_".toSlice()).toSlice();
	return m
	    .concat(host.toSlice()).toSlice()
	    .concat("_".toSlice()).toSlice()
	    .concat(iToHex(abi.encodePacked(tag)).toSlice());
    }
    
    function volatileSet(bytes32 tag, bytes32 value) public {
	address caller = msg.sender;
	string memory env = toEnv(activeHost, caller, tag);
	vm.setEnv(env, iToHex(abi.encodePacked(value)));
    }
    function volatileGet(bytes32 tag) public returns(bytes32) {
	address caller = msg.sender;
	string memory env = toEnv(activeHost, caller, tag);
	return vm.envOr(env, bytes32(""));
    }

    // Currently active host
    string activeHost = "default";
    function switchHost(string memory host) internal {
	activeHost = host;
    }
    function resetHost(address subject) internal {
	// Reset the data for this host
	// If 0, Host loses all their data
    }

    function iToHex(bytes memory buffer) public pure returns (string memory) {
        bytes memory converted = new bytes(buffer.length * 2);
        bytes memory _base = "0123456789abcdef";
        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
	}
        return string(abi.encodePacked("0x", converted));
    }
}
