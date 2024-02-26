pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {BIP32} from "../src/BIP32.sol";
import {HashForge} from "src/hash/HashForge.sol";

contract BIP32_Test is Test {
    BIP32 bip32;
    HashForge hasher;
    
    function setUp() public {
        hasher = new HashForge();
        bip32 = new BIP32(hasher);
    }

    function testSHA512() public view {
        bytes memory data = "test";
        bytes memory result = hasher.sha512(abi.encodePacked(data));
        bytes memory expected = bytes(hex"ee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db27ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff");
        //print the result to the console
        require(keccak256(result) == keccak256(expected)); 
    }
    
    function testSplitFunction() public view {
        bytes memory data = hasher.sha512("test");
        (bytes32 left, bytes32 right) = bip32.split(data);   
        bytes32 expected_left  = 0xee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db2;
        bytes32 expected_right = 0x7ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff;   
        require(left == expected_left);
        require(right == expected_right);
    }

    function testDeriveKey() public view {
        bytes memory seed = abi.encodePacked("MySecretPassword");
  
        // derive the master key directly and when using a seed and a path
        (BIP32.ExtendedPrivateKey memory xPriv) = bip32.newFromSeed(seed);
        (BIP32.ExtendedPrivateKey memory pathXPriv, BIP32.ExtendedPublicKey memory cXPub) = bip32.deriveChildKeyPairFromPath(seed, "m");
        require(xPriv.key == pathXPriv.key);
    }

    function testDeriveNonHardenedKey() public view {
        bytes memory seed = abi.encodePacked("MySecretPassword");

        // derive the master key directly and when using a seed and a path
        (BIP32.ExtendedPrivateKey memory xPriv) = bip32.newFromSeed(seed);

        // non hardened child derivation using index and path
        (BIP32.ExtendedPrivateKey memory cxPriv, BIP32.ExtendedPublicKey memory cxPub) = bip32.deriveChildKeyPair(xPriv, 0);
        (BIP32.ExtendedPrivateKey memory pathCXPriv, BIP32.ExtendedPublicKey memory pathCXPub) = bip32.deriveChildKeyPairFromPath(seed, "m/0");
        require(cxPriv.key == pathCXPriv.key); 
    }

    function testDeriveHardenedKey() public view {
        bytes memory seed = abi.encodePacked("MySecretPassword");

        // derive the master key directly and when using a seed and a path
        (BIP32.ExtendedPrivateKey memory xPriv) = bip32.newFromSeed(seed);

        // hardened child derivation using index and path
        (BIP32.ExtendedPrivateKey memory hcxPriv, BIP32.ExtendedPublicKey memory hcxPub) = bip32.deriveChildKeyPair(xPriv, 2147483648);
        (BIP32.ExtendedPrivateKey memory pathHCXPriv, BIP32.ExtendedPublicKey memory pathHCXPub) = bip32.deriveChildKeyPairFromPath(seed, "m/0'");
        require(hcxPriv.key == pathHCXPriv.key);
    }

    function testDeriveNonHardenedFromHardenedKey() public view {
        bytes memory seed = abi.encodePacked("MySecretPassword");

        // derive the master key directly and when using a seed and a path
        (BIP32.ExtendedPrivateKey memory xPriv) = bip32.newFromSeed(seed);

        // hardened child derivation using index and path
        (BIP32.ExtendedPrivateKey memory hcxPriv, BIP32.ExtendedPublicKey memory hcxPub) = bip32.deriveChildKeyPair(xPriv, 2147483648);
        
        // derive a non hardened child key from a hardened one (mixing both)
        (BIP32.ExtendedPrivateKey memory nhcxPriv, BIP32.ExtendedPublicKey memory nhcxPub) = bip32.deriveChildKeyPair(hcxPriv, 0);
        (BIP32.ExtendedPrivateKey memory pathNHCXPriv, BIP32.ExtendedPublicKey memory pathNHCXPub) = bip32.deriveChildKeyPairFromPath(seed, "m/0'/0");
        require(nhcxPriv.key == pathNHCXPriv.key);
    }
    
    function testDeriveChildPubKeyFromParentPubKey() public view {
        bytes memory seed = abi.encodePacked("MySecretPassword");

        // derive the master key directly and when using a seed and a path
        (BIP32.ExtendedPrivateKey memory xPriv) = bip32.newFromSeed(seed);

        // derive the master public key
        (BIP32.ExtendedPublicKey memory xPub) = bip32.derivePubKey(xPriv);
        
        // derive a child public key from the master public key
        (BIP32.ExtendedPrivateKey memory cxPriv, BIP32.ExtendedPublicKey memory cxPub) = bip32.deriveChildKeyPair(xPriv, 0);
        (BIP32.ExtendedPublicKey memory childXPub) = bip32.derivePubKeyFromParentPubKey(xPub, 0);
        require(keccak256(childXPub.key) == keccak256(cxPub.key));
    }

    function testDeriveChildPubKeyFromParentPubKeyFail() public view {
        bytes memory seed = abi.encodePacked("MySecretPassword");

        // derive the master key directly and when using a seed and a path
        (BIP32.ExtendedPrivateKey memory xPriv) = bip32.newFromSeed(seed);

        // derive the master public key
        (BIP32.ExtendedPublicKey memory xPub) = bip32.derivePubKey(xPriv);
        
        // derive a child public key from the master public key
        (BIP32.ExtendedPrivateKey memory cxPriv, BIP32.ExtendedPublicKey memory cxPub) = bip32.deriveChildKeyPair(xPriv, 2147483648);
        try bip32.derivePubKeyFromParentPubKey(xPub, 2147483648) {
            revert("Should have failed");
        } catch Error(string memory reason) {
            // Pass the test because the function call should fail for hardened derivation from parent pubkey
        }   
    }
}