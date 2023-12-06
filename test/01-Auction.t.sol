// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AndromedaForge} from "../src/AndromedaForge.sol";
import {Test, console2} from "forge-std/Test.sol";
import {LeakyAuction, SealedAuction} from "../src/01-Auction.sol";

contract SimpleAuctionTest is Test {
    AndromedaForge andromeda;

    address alice;
    address bob;

    function setUp() public {
	andromeda = new AndromedaForge();
	vm.prank(address(0x4));
	
	alice = vm.addr(uint(keccak256("alice")));
	bob = vm.addr(uint(keccak256("bob")));	
    }

    function test_leaky() public {
	LeakyAuction auc = new LeakyAuction();

	vm.prank(alice);
	auc.submitBid(10);
	vm.prank(bob);
	auc.submitBid(8);

	vm.roll(3);
	auc.conclude();
	assertEq(auc.secondPrice(), 8);
    }

    function test_sealed() public {
	SealedAuction auc = new SealedAuction(andromeda);

	// Have a Kettle initialize the key
	(bytes memory xPub, bytes memory att) = auc.offchain_Bootstrap();
	auc.onchain_Bootstrap(xPub, att);

	// Submit encrypted orders
	bytes memory aBid = auc.encryptOrder(10, bytes32(uint(0xdead2123)));
	bytes memory bBid = auc.encryptOrder( 8, bytes32(uint(0xcafe1232)));
	vm.prank(alice);
	auc.submitEncrypted(aBid);
	vm.prank(bob);
	auc.submitEncrypted(bBid);

	vm.roll(3);

	// Off chain compute the solution
	(uint secondPrice, bytes memory sig2) = auc.offline_Finalize();

	// Subit the solution onchain
	auc.onchain_Finalize(secondPrice, sig2);
	assertEq(auc.secondPrice(), 8);
    }
}
