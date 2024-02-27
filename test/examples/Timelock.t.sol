// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AndromedaRemote} from "src/AndromedaRemote.sol";
import {SigVerifyLib} from "automata-dcap-v3-attestation/utils/SigVerifyLib.sol";

import {Test, console2} from "forge-std/Test.sol";
import "src/crypto/secp256k1.sol";
import {NewKeyManager_v0} from "src/NewKeyManager.sol";
import {PKE, Curve} from "src/crypto/encryption.sol";
import {Timelock} from "src/examples/Timelock.sol";
import {BIP32} from "src/BIP32.sol";
import {HashForge} from "src/hash/HashForge.sol";

contract TimelockTest is Test {
    AndromedaRemote andromeda;
    NewKeyManager_v0 keymgr;
    BIP32 bip32;
    HashForge hasher;

    address alice;
    address bob;

    function setUp() public {
        hasher = new HashForge();
        bip32 = new BIP32(hasher);
        SigVerifyLib lib = new SigVerifyLib();
        andromeda = new AndromedaRemote(address(lib));
        andromeda.initialize();
        vm.warp(1701528486);

        andromeda.setMrSigner(
            bytes32(
                0x1cf2e52911410fbf3f199056a98d58795a559a2e800933f7fcd13d048462271c
            ),
            true
        );

        // To ensure we don't use the same address with volatile storage
        vm.prank(vm.addr(uint256(keccak256("examples/Timelock.t.sol"))));
        keymgr = new NewKeyManager_v0(address(andromeda), bip32);
        (address xPub, bytes memory att) = keymgr.offchain_Bootstrap();
        keymgr.onchain_Bootstrap(xPub, att);

        alice = vm.addr(uint256(keccak256("alice")));
        bob = vm.addr(uint256(keccak256("bob")));
    }

    function test_timelock() public {
        Timelock timelock = new Timelock(keymgr);

        // Initialize the derived public key
        assertEq(timelock.isInitialized(), false);
        uint32 index = 0;
        (bytes memory dPub, bytes memory sig) = keymgr.offchain_DeriveKey(
            address(timelock), index
        );
        keymgr.onchain_DeriveKey(address(timelock), dPub, sig, index);
        assertEq(timelock.isInitialized(), true);

        // Submit encrypted orders
        string memory message = "Suave timelock test message!32xr";
        bytes memory ciph = timelock.encryptMessage(
            message,
            bytes32(uint(0xdead2123))
        );
        timelock.submitEncrypted(ciph);

        vm.roll(60);

        // Off chain compute the solution
        bytes memory output = timelock.decrypt(ciph);
        string memory dec = string(output);
        assertEq(message, dec);
    }
}
