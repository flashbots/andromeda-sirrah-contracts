pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {BIP32Forge} from "../src/BIP32Forge.sol";
import {AndromedaForge} from "src/AndromedaForge.sol";

contract BIP32_Test is Test {
    BIP32Forge bip32;

    function setUp() public {
        bip32 = new BIP32Forge();
    }

    function testSplitFunction() public view{
        bytes memory data = "test";
        (bytes32 left, bytes32 right) = bip32.split(data);
        //console2.logBytes32(left);
        //console2.logBytes32(right);    
        bytes32 expected_left  = 0xee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db2;
        bytes32 expected_right = 0x7ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff;   
        require(left == expected_left);
        require(right == expected_right);
    }
    function testSHA512() public view{
        bytes memory data = "test";
        bytes memory result = bip32.sha512(abi.encodePacked(data));
        bytes memory expected = bytes(hex"ee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db27ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff");
        //print the result to the console
        require(keccak256(result) == keccak256(expected)); 
    }
    
    function testDeriveKey() public view{
        bytes memory seed = abi.encodePacked(hex"000102030405060708090a0b0c0d0e0f");
        //bytes memory seed = abi.encodePacked(bip32.localRandom());
        uint256 seed_length = seed.length;
        console2.logUint(seed_length);
        
        (BIP32Forge.ExtendedPrivateKey memory xPriv) = bip32.newFromSeed(seed);
        console2.logBytes32(xPriv.key);
        

        //(BIP32Forge.ExtendedPrivateKey memory xxPriv, BIP32Forge.ExtendedPublicKey memory cXPub) = bip32.deriveChildKeyPair(xPriv, 0);
        //console2.logBytes32(xxPriv.attributes.chainCode);
        //(BIP32Forge.ExtendedPrivateKey memory cXPriv, BIP32Forge.ExtendedPublicKey memory cXPub) = bip32.deriveChildKeyPairFromPath(seed, "m");
        //console2.logBytes32(cXPriv.key);
        

    }
}