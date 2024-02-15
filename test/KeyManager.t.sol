// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {KeyManager_v0} from "../src/KeyManager.sol";
import {PKE} from "../src/crypto/encryption.sol";
import {AndromedaForge} from "src/AndromedaForge.sol";
import "forge-std/Vm.sol";

contract KeyManager_v0_Test is Test {
    AndromedaForge andromeda;
    KeyManager_v0 keymgr;

    Vm.Wallet alice;
    Vm.Wallet bob;
    Vm.Wallet carol;

    function setUp() public {
        andromeda = new AndromedaForge();
        vm.prank(vm.addr(uint(keccak256("KeyManager.t.sol"))));
        keymgr = new KeyManager_v0(address(andromeda));

        alice = vm.createWallet("alice");
        bob = vm.createWallet("bob");
    }

    function testKeyManager() public {
        (bytes32 left, bytes32 right) = keymgr.testing("test");
        // log left and right
        console2.logBytes32(left);
        console2.logBytes32(right);


        // 1. Bootstrap
        // 1a. Offchain generate the key
        andromeda.switchHost("alice");
        (address xPub, bytes memory att) = keymgr.offchain_Bootstrap();
        // 1b. Post the key and attestation on-chain
        keymgr.onchain_Bootstrap(xPub, att);

        // 2. Register a new node
        // 2a. Offchain generate a register request
        andromeda.switchHost("bob");
        (address bob_kettle, bytes memory bPub, bytes memory attB) = keymgr
            .offchain_Register();
        // 2b. Onchain submit the request
        keymgr.onchain_Register(bob_kettle, bPub, attB);

        // 2.1 Register a new node
        // 2.1a. Offchain generate a register request
        andromeda.switchHost("charlie");
        (address charlie_kettle, bytes memory cPub, bytes memory attC) = keymgr
            .offchain_Register();
        // 2.1b. Onchain submit the request
        keymgr.onchain_Register(charlie_kettle, cPub, attC);

        assert(bob_kettle != charlie_kettle);

        // 3. Help onboard a new node
        // 3a. Offchain generate a ciphertext with the key
        andromeda.switchHost("alice");
        bytes memory ciphertext = keymgr.offchain_Onboard(bob_kettle);
        // 3b. Onchain post the ciphertext
        keymgr.onchain_Onboard(bob_kettle, ciphertext);
        // 3c. Load the data received
        andromeda.switchHost("bob");
        keymgr.finish_Onboard(ciphertext);

        // 3.1. Help onboard a second node
        ciphertext = keymgr.offchain_Onboard(charlie_kettle);
        // 3.1b. Onchain post the ciphertext
        keymgr.onchain_Onboard(charlie_kettle, ciphertext);
        // 3.1c. Load the data received
        andromeda.switchHost("charlie");
        keymgr.finish_Onboard(ciphertext);
    }

    function testDerived() public {
        // Do the bootstrap
        (address xPub, bytes memory att) = keymgr.offchain_Bootstrap();
        keymgr.onchain_Bootstrap(xPub, att);

        // Show the derived key associated with this contract.
        (bytes memory dPub, bytes memory sig) = keymgr.offchain_DeriveKey(
            address(this)
        );
        keymgr.onchain_DeriveKey(address(this), dPub, sig);

        bytes32 dPriv = keymgr.derivedPriv();
        assertEq(PKE.derivePubKey(dPriv), keymgr.derivedPub(address(this)));
    }
}
