// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {IAndromeda} from "src/IAndromeda.sol";
import {Secp256k1} from "src/crypto/secp256k1.sol";
import {PKE, Curve} from "src/crypto/encryption.sol";
import {BIP32} from "src/BIP32.sol";

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

    function _derivedPriv(address a) internal virtual returns (bytes32);

    // Key derivation for encryption

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
        // TODO followup: disover an API to allow key derivation with an index/path for hardened and non-hardened key derivations
        bytes32 dPriv = _derivedPriv(a);
        dPub = PKE.derivePubKey(dPriv);
        bytes32 digest = keccak256(abi.encodePacked(a, dPub));
        sig = Secp256k1.sign(uint256(xPriv()), digest);
        require(Secp256k1.verify(xPub, digest, sig));
    }
}

contract KeyManager_v0 is KeyManagerBase {
    IAndromeda public Suave;
    BIP32 public bip32;

    constructor(address _Suave) {
        Suave = IAndromeda(_Suave);
        bip32 = new BIP32(Suave);
    }

    function addressToBIP32HardenedIndex(address a) internal view returns (uint32) {
        return uint32(uint256(keccak256(abi.encodePacked(a))) | bip32.HARDENED_START_INDEX());
    }

    // Any contract in confidential mode can request a
    // hardened derived key
    function _derivedPriv(address a) internal override returns (bytes32) {
        bytes32 seed = getSeed();
        uint32 addrIndex = addressToBIP32HardenedIndex(a);
        (BIP32.ExtendedPrivateKey memory _xPriv, BIP32.ExtendedPublicKey memory _xPub) = bip32.deriveChildKeyPairFromSeed(abi.encodePacked(seed), addrIndex);
        return _xPriv.key;
    }

    function derivedPriv() public returns (bytes32) {
        return _derivedPriv(msg.sender);
    }

    function getSeed() private returns (bytes32) {
        return Suave.volatileGet("seed");
    }

    function setSeed(bytes32 seed) private {
        Suave.volatileSet("seed", seed);
    } 

    function xPriv() internal override returns (bytes32) {
        return bip32.newFromSeed(abi.encodePacked(getSeed())).key;
    }

    // 1. Bootstrap phase
    function offchain_Bootstrap() public returns (address _xPub, bytes memory att) {
        require(xPub == address(0));
        bytes32 seed = Suave.localRandom();
        bytes32 xPrivKey = bip32.newFromSeed(abi.encodePacked(seed)).key;
        _xPub = Secp256k1.deriveAddress(uint256(xPrivKey));
        setSeed(seed);
        att = Suave.attestSgx(keccak256(abi.encodePacked("xPub", _xPub)));
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
        require(keccak256(registry[addr]) == keccak256(bytes("")));

        bytes32 myPriv = Suave.sealingKey("myPriv");
        myPub = PKE.derivePubKey(myPriv);
        addr = address(Secp256k1.deriveAddress(uint256(myPriv)));
        att = Suave.attestSgx(keccak256(abi.encodePacked("myPub", myPub, addr)));
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
        return PKE.encrypt(registry[newkettle], r, abi.encodePacked(getSeed()));
    }

    event Onboard(address addr, bytes ciphertext);

    function onchain_Onboard(address addr, bytes memory ciphertext) public {
        // Note: nothing guarantees all ciphertexts on chain are valid
        emit Onboard(addr, ciphertext);
    }

    function finish_Onboard(bytes memory ciphertext) public {
        bytes32 myPriv = Suave.sealingKey("myPriv");
        bytes32 seed = abi.decode(PKE.decrypt(myPriv, ciphertext), (bytes32));
        bytes32 _xPriv = bip32.newFromSeed(abi.encodePacked(seed)).key;
        require(Secp256k1.deriveAddress(uint256(_xPriv)) == xPub);
        setSeed(seed);
    }
}
