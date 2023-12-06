// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";

import "../src/crypto/encryption.sol";
import "../src/crypto/secp256k1.sol";

contract CryptoTest is Test {

    function test_signing() public {
	bytes32 sk = bytes32(0xce4cd60396002795176e7597cac85f4b1515cd6f367d78f285c7974fa1a753fa);
	address a = Secp256k1.deriveAddress(uint(sk));
	bytes32 digest = keccak256(abi.encodePacked("hi"));
	bytes memory sig = Secp256k1.sign(uint(sk), digest);
	assertTrue(Secp256k1.verify(a, digest, sig));
    }

    function test_address() public {
	bytes32 sk = bytes32(0x4646464646464646464646464646464646464646464646464646464646464646);
	(uint qx, uint qy) = Secp256k1.derivePubKey(uint(sk));
	address a = Secp256k1.deriveAddress(uint(sk));
	bytes memory ser = bytes.concat(bytes32(qx), bytes32(qy));
	assertEq(address(0x9d8A62f656a8d1615C1294fd71e9CFb3E4855A4F), a);
    }

    function test_encryption() public {
	bytes32 secretKey = bytes32(uint(0x4646464646464646464646464646464646464646464646464646464646464646));
	Curve.G1Point memory pub =
	    Curve.g1mul(Curve.P1(), uint(secretKey));
	
	bytes memory message = bytes("hello there suave,      #32bytes");
	
	// Encrypt the message to the auction contract
	bytes32 r = bytes32(uint(0x1231251)); 
	bytes memory ciphertext = PKE.encrypt(abi.encodePacked(pub.X,pub.Y),
					      r, message);

	// Decrypt the message (using hardcoded auction contract secretkey):
	bytes memory message2 = PKE.decrypt(secretKey, ciphertext);
	assertEq(message, message2);
    }
}
