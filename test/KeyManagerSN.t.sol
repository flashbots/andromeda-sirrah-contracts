// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {KeyManagerSN} from "../src/KeyManagerSN.sol";
import {AndromedaForge} from "src/AndromedaForge.sol";
import "forge-std/Vm.sol";

contract KeyManagerSNTest is Test {
    AndromedaForge andromeda;
    KeyManagerSN keymgr;

    Vm.Wallet alice;
    Vm.Wallet bob;
    Vm.Wallet carol;

    function setUp() public {
	andromeda = new AndromedaForge();
	keymgr = new KeyManagerSN(andromeda);

	alice = vm.createWallet("alice");
	bob = vm.createWallet("bob");
	/*
	bob = vm.createWallet("bob");
	carol = vm.createWallet("carol");
	vm.deal(alice.addr, 100);
	vm.deal(bob.addr, 100);
	vm.deal(carol.addr, 100);*/
    }

    function testKeyManager() public {

	// 1. Bootstrap
	// 1a. Offchain generate the key
	andromeda.switchHost("alice");
	(bytes memory xPub, bytes memory att) = keymgr.offchain_Bootstrap();

	// 1b. Post the key and attestation on-chain
	vm.startBroadcast();
	keymgr.onchain_Bootstrap(xPub, att);
	vm.stopBroadcast();

	// 2. Register a new node
	// 2a. Offchain generate a register request
	andromeda.switchHost("bob");
	(address bob_kettle, bytes memory bPub, bytes memory attB) = keymgr.offchain_Register();
	
	// 2b. Onchain submit the request
	vm.startBroadcast();	
	keymgr.onchain_Register(bob_kettle, bPub, attB);
	vm.stopBroadcast();

	// 3. Help onboard a new node
	// 3a. Offchain generate a ciphertext with the key
	andromeda.switchHost("alice");
	(bytes memory ciphertext) = keymgr.offchain_Onboard(bob_kettle);
	// 3b. Onchain post the ciphertext
	keymgr.onchain_Onboard(bob_kettle, ciphertext);
	// 3c. Load the data received
	andromeda.switchHost("bob");
	keymgr.finish_Onboard(ciphertext);
    }

}
