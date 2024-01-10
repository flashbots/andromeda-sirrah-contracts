// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {IAndromeda} from "src/IAndromeda.sol";
import {Secp256k1} from "src/crypto/secp256k1.sol";
import {PKE, Curve} from "src/crypto/encryption.sol";

abstract contract KeyManagerBase {
    // This base class provides the functionality of a singleton
    // Private Key holder. It allows many applications to share the
    // same bootstrapped instance.

    // Anyone can see the master public key
    address public xPub;

    // Attestation is now possible using the caller as domain
    // separator
    function attest(bytes32 appData) public returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked(msg.sender, appData));
        return Secp256k1.sign(uint256(xPriv()), digest);
    }

    function verify(address caller, bytes32 appData, bytes memory sig) public view returns (bool) {
        bytes32 digest = keccak256(abi.encodePacked(caller, appData));
        return Secp256k1.verify(xPub, digest, sig);
    }

    //////////////////////////////////
    // To be implemented by subclasses
    //////////////////////////////////
    
    // Only the contract in confidential mode can access the
    // master private key
    function xPriv() internal virtual returns (bytes32);
    

    // Key derivation for encryption
    
    // Any contract in confidential mode can request a
    // hardened derived key
    function _derivedPriv(address a) public returns (bytes32) {
        return keccak256(abi.encodePacked(a, xPriv()));
    }

    function derivedPriv() public returns (bytes32) {
        return _derivedPriv(msg.sender);
    }

    // Because we are using hardened derivation, for each
    // contract we will need someone to sign it off chain
    mapping(address => bytes) public derivedPub;

    function onchain_DeriveKey(
        address a,
        bytes memory dPub,
        // Signature from a valid kettle
        bytes memory sig
    ) public {
        bytes32 digest = keccak256(abi.encodePacked(a, dPub));
        require(Secp256k1.verify(xPub, digest, sig));
        derivedPub[a] = dPub;
    }

    function offchain_DeriveKey(address a) public returns (bytes memory dPub, bytes memory sig) {
        bytes32 dPriv = _derivedPriv(a);
        dPub = PKE.derivePubKey(dPriv);
        bytes32 digest = keccak256(abi.encodePacked(a, dPub));
        sig = Secp256k1.sign(uint256(xPriv()), digest);
        require(Secp256k1.verify(xPub, digest, sig));
    }
}

contract KeyManager_v0 is KeyManagerBase {
    IAndromeda public Suave;

    constructor(address _Suave) {
        Suave = IAndromeda(_Suave);
    }

    // SUAVE contract that emulates Secret Network (SN) key management
    bytes32 public constant mrenclave = 0x0; // TODO

    // 1. Bootstrap phase
    function offchain_Bootstrap() public returns (address _xPub, bytes memory att) {
        bytes32 xPriv_ = Suave.localRandom();
        _xPub = Secp256k1.deriveAddress(uint256(xPriv_));
        Suave.volatileSet("xPriv", xPriv_);
        att = Suave.attestSgx(keccak256(abi.encodePacked("xPub", _xPub)));
    }

    function xPriv() internal override returns (bytes32) {
        return Suave.volatileGet("xPriv");
    }

    function onchain_Bootstrap(address _xPub, bytes memory att) public {
        require(xPub == address(0)); // only once
        require(Suave.verifySgx(address(this), keccak256(abi.encodePacked("xPub", _xPub)), att));
        xPub = _xPub;
    }

    // 2. New node register phase
    // Mapping to nonzero indicates valid Kettle
    mapping(address => bytes) registry;

    function offchain_Register() public returns (address addr, bytes memory myPub, bytes memory att) {
        bytes32 myPriv = Suave.sealingKey("myPriv");
        bytes memory myPub = PKE.derivePubKey(myPriv);
        address addr = address(Secp256k1.deriveAddress(uint256(myPriv)));
        bytes memory att = Suave.attestSgx(keccak256(abi.encodePacked("myPub", myPub, addr)));
        return (addr, myPub, att);
    }

    function onchain_Register(address addr, bytes memory myPub, bytes memory att) public {
        require(keccak256(registry[addr]) == keccak256(bytes("")));
        require(Suave.verifySgx(address(this), keccak256(abi.encodePacked("myPub", myPub, addr)), att));
        registry[addr] = myPub;
    }

    // 3. Onboard a new node phase
    // 3a. A Kettle that already has the key onboards the new node
    function offchain_Onboard(address newkettle) public returns (bytes memory ciphertext) {
        bytes32 r = Suave.localRandom();
        return PKE.encrypt(registry[newkettle], r, abi.encodePacked(xPriv()));
    }

    event Onboard(address addr, bytes ciphertext);

    function onchain_Onboard(address addr, bytes memory ciphertext) public {
        // Note: nothing guarantees all ciphertexts on chain are valid
        emit Onboard(addr, ciphertext);
    }

    function finish_Onboard(bytes memory ciphertext) public {
        bytes32 myPriv = Suave.sealingKey("myPriv");
        bytes32 xPriv_ = abi.decode(PKE.decrypt(myPriv, ciphertext), (bytes32));
        require(Secp256k1.deriveAddress(uint256(xPriv_)) == xPub);
        Suave.volatileSet("xPriv", xPriv_);
    }
}
