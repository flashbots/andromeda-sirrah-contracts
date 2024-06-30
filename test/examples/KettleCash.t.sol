// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AndromedaRemote,SigVerifyLib} from "src/AndromedaRemote.sol";
import {Test, console2} from "forge-std/Test.sol";

import {KeyManager_v0} from "src/KeyManager.sol";
//import {KeyManager_v0_Test} from "test/KeyManager.t.sol";
import {KettleCash, Check} from "src/examples/KettleCash.sol";

contract KettleCashTest is Test {
    AndromedaRemote andromeda;
    KeyManager_v0 keymgr;
    KettleCash cash;

    address alice;
    address bob;

    function setUp_Bootstrap() public {
        andromeda.switchHost("bootstrap");
        (address xPub, bytes memory att) = keymgr.offchain_Bootstrap();
        keymgr.onchain_Bootstrap(xPub, att);

	(bytes memory dPub, bytes memory sig) = keymgr.offchain_DeriveKey(address(cash));
	keymgr.onchain_DeriveKey(address(cash), dPub, sig);
    }
    function setUp_Onboard(string memory newHost) public {
        // 2. Register a new node
	andromeda.switchHost(newHost);
        (address kettle, bytes memory bPub, bytes memory attB) = keymgr
            .offchain_Register();
        keymgr.onchain_Register(kettle, bPub, attB);

        // 3. Help onboard a new node
        // 3a. Offchain generate a ciphertext with the key
        andromeda.switchHost("bootstrap");
        bytes memory ciphertext = keymgr.offchain_Onboard(kettle);
        // 3b. Onchain post the ciphertext
        keymgr.onchain_Onboard(kettle, ciphertext);
        // 3c. Load the data received
        andromeda.switchHost(newHost);
        keymgr.finish_Onboard(ciphertext);

        // 3.1. Help onboard a second node
        andromeda.switchHost("bootstrap");
        ciphertext = keymgr.offchain_Onboard(kettle);
        // 3.1b. Onchain post the ciphertext
        keymgr.onchain_Onboard(kettle, ciphertext);
        // 3.1c. Load the data received
        andromeda.switchHost(newHost);
        keymgr.finish_Onboard(ciphertext);
    }
	
    function setUp() public {
        SigVerifyLib lib = new SigVerifyLib();
        andromeda = new AndromedaRemote(address(lib));
        andromeda.initialize();

	vm.prank(vm.addr(uint256(keccak256("examples/EChecks.t.sol"))));
        keymgr = new KeyManager_v0(address(andromeda));

	cash = new KettleCash(keymgr);

        alice = vm.addr(uint256(keccak256("alice")));
        bob = vm.addr(uint256(keccak256("bob")));

	setUp_Bootstrap();
	setUp_Onboard("alice");
	setUp_Onboard("bob");
    }

    function test_echecks() public {
	andromeda.switchHost("alice");
	address alice_kettle = cash.offchain_ThisKettle();
	console2.logAddress(alice_kettle);
	andromeda.switchHost("bob");
	address bob_kettle = cash.offchain_ThisKettle();
	console2.logAddress(bob_kettle);

	// On chain deposit
	andromeda.switchHost("alice");
	vm.prank(alice);
	vm.deal(alice, 1 ether);
	Check memory c = cash.onchain_Deposit{value: 1 ether}(alice_kettle);
	console2.logUint(c.amount);
	assert(!cash.cashed(cash.CheckSerial(c)));
	assert(!cash._IsSpent(c));

	// Alice deposits her check into her own Kettle
	cash.offchain_DepositCheck(c);
	assert(cash._IsSpent(c));
	assert(cash.offchain_QueryBalance(alice) == 1 ether);

	// Can't deposit twice
	vm.expectRevert();
	cash.offchain_DepositCheck(c);

	// Alice issues a check to pay Bob at Bob's kettle
	vm.prank(alice);
	Check memory c2 = cash.offchain_IssueCheck(bob, bob_kettle, 0.3 ether);
	assert(cash.offchain_QueryBalance(alice) == 0.7 ether);

	// Can't cash at the wrong kettle
	andromeda.switchHost("alice");
	vm.expectRevert();
	cash.offchain_DepositCheck(c2);

	// Let's try to deposit the check at Bob's kettle
	andromeda.switchHost("bob");
	assert(!cash._IsSpent(c2));
	cash.offchain_DepositCheck(c2);
	assert(cash.offchain_QueryBalance(bob) == 0.3 ether);
	assert(cash._IsSpent(c2));
	
	// To withdraw, Issue a check to kettle address(0)
	vm.prank(bob);
	Check memory c3 = cash.offchain_IssueCheck(bob, address(0), 0.2 ether);

	// We can cash the withdrawal check on-chain
	assert(!cash.cashed(cash.CheckSerial(c3)));
	cash.onchain_Withdraw(c3);
	assert(bob.balance == 0.2 ether);

	// Can't cash twice
	vm.expectRevert();
	cash.onchain_Withdraw(c3);
    }
}
