// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {AndromedaForge} from "src/AndromedaForge.sol";
import {Secp256k1} from "src/crypto/secp256k1.sol";
import {Signing,PKE,Curve} from "src/crypto/encryption.sol";

abstract contract KeyManagerBase {
    // Anyone can see the master public key
    address xPub;

    // Mapping to nonzero indicates valid Kettle
    mapping ( address => bytes ) registry;

    // Only the contract in confidential mode can access the
    // master private key
    function xPriv() internal virtual returns(bytes32);

    // Any contract in confidential mode can request a
    // hardened derived key
    function _derivedPriv(address a) public returns (bytes32) {
	return keccak256(abi.encodePacked(a,xPriv()));
    }
    function derivedPriv() public returns (bytes32) {
	return _derivedPriv(msg.sender);
    }

    // Because we are using hardened derivation, for each 
    // contract we will need someone to sign it off chain
    mapping (address => bytes) public derivedPub;
    function onchain_DeriveKey(address a,
			   bytes memory dPub,
			   // Signature from a valid kettle
			   uint8 v, bytes32 r, bytes32 s)
    public
    returns(bytes32) {
	bytes32 digest = keccak256(abi.encodePacked(a,dPub));
	address signer = ecrecover(digest, v, r, s);
	require(signer == xPub);
	derivedPub[a] = dPub;
    }

    function offchain_DeriveKey(address a)
    public
    returns(bytes memory dPub, uint8 v, bytes32 r, bytes32 s) {
	bytes32 dPriv = _derivedPriv(a);
	dPub = PKE.derivePubKey(dPriv);
	bytes32 digest = keccak256(abi.encodePacked(a,dPub));
	(v,r,s) = Secp256k1.sign(uint(xPriv()), digest, 0x232343);
    }
}

contract KeyManagerSN is KeyManagerBase {
    AndromedaForge Suave;

    constructor(AndromedaForge _Suave) {
	Suave = _Suave;
    }
    
    // SUAVE contract that emulates Secret Network (SN) key management
    bytes32 public constant mrenclave = 0x0; // TODO
    
    // 1. Bootstrap phase
    function offchain_Bootstrap() public returns(address _xPub, bytes memory att) {
	bytes32 xPriv = Suave.localRandom();
	_xPub = Secp256k1.deriveAddress(uint(xPriv));
	Suave.volatileSet("xPriv", xPriv);
	att = Suave.attestSgx("xPub", keccak256(abi.encodePacked(_xPub)));
    }

    function xPriv() internal override returns(bytes32) {
	return Suave.volatileGet("xPriv");
    }
   
    function onchain_Bootstrap(address _xPub, bytes memory att)
    public
    {
	require(xPub == address(0)); // only once
	Suave.verifySgx(address(this), "xPub", keccak256(abi.encodePacked(_xPub)), att);
	xPub = _xPub;
    }
    
    // 2. New node register phase    
    function offchain_Register() public returns(address, bytes memory, bytes memory) {
	bytes32 myPriv = Suave.localRandom();
	bytes memory myPub = PKE.derivePubKey(myPriv);
	address addr = address(Secp256k1.deriveAddress(uint(myPriv)));
	Suave.volatileSet("myPriv", myPriv);
	bytes memory att = Suave.attestSgx("myPub", keccak256(abi.encode(myPub, addr)));
	return (addr, myPub, att);
    }

    function onchain_Register(address addr, bytes memory myPub, bytes memory att) public {
	require(keccak256(registry[addr]) == keccak256(bytes("")));
	Suave.verifySgx(address(this), "myPub", keccak256(abi.encode(myPub, addr)), att);
	registry[addr] = myPub;
    }
    
    // 3. Onboard a new node phase
    // 3a. A Kettle that already has the key onboards the new node
    function offchain_Onboard(address newkettle) public returns(bytes memory ciphertext) {
	bytes32 r = Suave.localRandom();
	return Crypto.encrypt(registry[newkettle], r,
			      abi.encodePacked(xPriv()));
    }

    event Onboard(address addr, bytes ciphertext);    
    function onchain_Onboard(address addr, bytes memory ciphertext) public {
	// Note: nothing guarantees all ciphertexts on chain are valid
	emit Onboard(addr, ciphertext);
    }

    function finish_Onboard(bytes memory ciphertext) public {
	bytes32 myPriv = Suave.volatileGet("myPriv");
	bytes32 xPriv = abi.decode(PKE.decrypt(myPriv, ciphertext), (bytes32));
	require(Secp256k1.deriveAddress(uint(xPriv)) == xPub);
	Suave.volatileSet("xPriv", xPriv);
    }
}

library Crypto {

    function encrypt(bytes memory pubkey, bytes32 r, bytes memory message) public view returns(bytes memory) {
	(uint gx, uint gy) = abi.decode(pubkey, (uint,uint));
	Curve.G1Point memory pub = Curve.G1Point(gx,gy);
	return PKE.encrypt(pub, r, message);
    }
}
