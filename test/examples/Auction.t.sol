// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AndromedaRemote} from "src/AndromedaRemote.sol";
import {SigVerifyLib} from "automata-dcap-v3-attestation/utils/SigVerifyLib.sol";

import {Test, console2} from "forge-std/Test.sol";

import {KeyManager_v0} from "src/KeyManager.sol";
import {LeakyAuction, SealedAuction, PKE, Curve} from "src/examples/Auction.sol";

contract SealedAuctionTest is Test {
    AndromedaRemote andromeda;
    KeyManager_v0 keymgr;

    address alice;
    address bob;

    function setUp() public {
        SigVerifyLib lib = new SigVerifyLib();
        andromeda = new AndromedaRemote(address(lib));
        andromeda.initialize();
        vm.warp(1701528486);

        andromeda.setMrSigner(bytes32(0x1cf2e52911410fbf3f199056a98d58795a559a2e800933f7fcd13d048462271c), true);

	// To ensure we don't use the same address with volatile storage
	vm.prank(vm.addr(uint256(keccak256("examples/Auction.t.sol"))));
        keymgr = new KeyManager_v0(address(andromeda));
        (address xPub, bytes memory att) = keymgr.offchain_Bootstrap();
        keymgr.onchain_Bootstrap(xPub, att);

        alice = vm.addr(uint256(keccak256("alice")));
        bob = vm.addr(uint256(keccak256("bob")));
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
        SealedAuction auc = new SealedAuction(keymgr, 2);

        // Initialize the derived public key
        assertEq(auc.isInitialized(), false);
        (bytes memory dPub, bytes memory sig) = keymgr.offchain_DeriveKey(address(auc));
        keymgr.onchain_DeriveKey(address(auc), dPub, sig);
        assertEq(auc.isInitialized(), true);

        // Submit encrypted orders
        bytes memory aBid = auc.encryptOrder(10, bytes32(uint256(0xdead2123)));
        bytes memory bBid = auc.encryptOrder(8, bytes32(uint256(0xcafe1232)));
        vm.prank(alice);
        auc.submitEncrypted(aBid);
        vm.prank(bob);
        auc.submitEncrypted(bBid);

        vm.roll(4);

        // Off chain compute the solution
        (uint256 secondPrice, bytes memory sig2) = auc.offchain_Finalize();

        // Subit the solution onchain
        auc.onchain_Finalize(secondPrice, sig2);
        assertEq(auc.secondPrice(), 8);
    }
}
