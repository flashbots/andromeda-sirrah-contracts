// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {AndromedaForge} from "src/AndromedaForge.sol";
import {Secp256k1} from "src/crypto/secp256k1.sol";
import {PKE,Curve} from "src/crypto/encryption.sol";


contract KeyManagerSN {
    AndromedaForge Suave;

    constructor(AndromedaForge _Suave) {
	Suave = _Suave;
    }
    
    // SUAVE contract that emulates Secret Network (SN) key management
    bytes32 public constant mrenclave = 0x0;
    bytes public xPub;

    mapping ( address => bytes /* encryption public key */ ) registry;
    
    // 1. Bootstrap phase
    function offchain_Bootstrap() public returns(bytes memory _xPub, bytes memory att) {
	bytes32 xPriv = Suave.localRandom();
	_xPub = Crypto.derivePubKey(xPriv);
	Suave.volatileSet("xPriv", xPriv);
	att = Suave.attestSgx("xPub", keccak256(abi.encodePacked(_xPub)));
    }
   
    function onchain_Bootstrap(bytes memory _xPub, bytes memory att) public {
	require(keccak256(xPub) == keccak256("")); // only once
	Suave.verifySgx(address(this), "xPub", keccak256(abi.encodePacked(_xPub)), att);
	xPub = _xPub;
    }
    
    // 2. New node register phase    
    function offchain_Register() public returns(address, bytes memory, bytes memory) {
	bytes32 myPriv = Suave.localRandom();
	bytes memory myPub = Crypto.derivePubKey(myPriv);
	address addr = address(Crypto.deriveAddress(myPriv));
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
	bytes32 xPriv = Suave.volatileGet("xPriv");
	return Crypto.encrypt(registry[newkettle], r, abi.encodePacked(xPriv));
    }

    event Onboard(address addr, bytes ciphertext);    
    function onchain_Onboard(address addr, bytes memory ciphertext) public {
	// Note: nothing guarantees all ciphertexts on chain are valid
	emit Onboard(addr, ciphertext);
    }

    function finish_Onboard(bytes memory ciphertext) public {
	bytes32 myPriv = Suave.volatileGet("myPriv");
	bytes32 xPriv = abi.decode(Crypto.decrypt(myPriv, ciphertext), (bytes32));
	require(keccak256(Crypto.derivePubKey(xPriv)) == keccak256(xPub));
	Suave.volatileSet("xPriv", xPriv);
    }
}

library Crypto {
    function derivePubKey(bytes32 privkey) public view returns(bytes memory) {
	Curve.G1Point memory p = PKE.derivePubKey(privkey);
	return abi.encode(p.X, p.Y);
    }
    function deriveAddress(bytes32 privkey) public pure returns(address) {
	(uint gx, uint gy) = Secp256k1.derivePubKey(uint(privkey));
	bytes memory pubkey = abi.encode(gx, gy);
	return address(bytes20(pubkey));
    }
    function encrypt(bytes memory pubkey, bytes32 r, bytes memory message) public view returns(bytes memory) {
	(uint gx, uint gy) = abi.decode(pubkey, (uint,uint));
	Curve.G1Point memory pub = Curve.G1Point(gx,gy);
	return PKE.encrypt(pub, r, message);
    }
    function decrypt(bytes32 privkey, bytes memory ciphertext) public view returns(bytes memory) {
	return PKE.decrypt(privkey, ciphertext);
    }
}
