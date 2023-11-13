// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {AndromedaForge} from "../src/AndromedaForge.sol";

contract AndromedaForgeTest is Test {
    AndromedaForge public andromeda;

    function setUp() public {
	andromeda = new AndromedaForge();
    }

    function test_attest() public {
	bytes32 tag = hex"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
	bytes32 msghash = keccak256(abi.encodePacked("hi"));

	// Attestation should check
	bytes memory att = andromeda.attestSgx(tag, msghash);
	andromeda.verifySgx(address(this), tag, msghash, att);

	// Unattested should not
	bytes32 msghash2 = keccak256(abi.encodePacked("hi2"));
	vm.expectRevert();
	andromeda.verifySgx(address(this), tag, msghash2, att);

	// Callers should have different domains
	vm.expectRevert();
	andromeda.verifySgx(address(andromeda), tag, msghash, att);
    }
   
    function test_SetGet() public {
	bytes32 value = keccak256(abi.encodePacked("hi"));

	// Initially it is 0
	bytes32 value2 = andromeda.volatileGet(bytes32("test"));
	require(value2 == "");

	// After setting it is hash("hi")
	andromeda.volatileSet(bytes32("test"), value);
	bytes32 value3 = andromeda.volatileGet(bytes32("test"));
	require(value3 == value);

	// Setting again overwrites
	bytes32 v2 = keccak256("asdf");
	andromeda.volatileSet(bytes32("test"), v2);
	bytes32 v2check = andromeda.volatileGet(bytes32("test"));
	require(v2check == v2);
    }
}
