// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {IAndromeda} from "src/IAndromeda.sol";
import {Secp256k1} from "src/crypto/secp256k1.sol";
import {PKE, Curve} from "src/crypto/encryption.sol";
import {BIP32} from "src/BIP32.sol";

abstract contract NewKeyManagerBase {
    // This base class provides the functionality of a singleton
    // Private Key holder. It allows many applications to share the
    // same bootstrapped instance.

    // Anyone can see the master public key
    address public xPub;

    // placeholder for hardened and non_hardened child indexes
    uint32 public constant HARDENED_START_INDEX = 2147483648;

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
    function seed() internal virtual returns (bytes32);

    function xPriv() internal virtual returns (bytes32);

    function _derivedPriv(address a, uint32 index) internal virtual returns (bytes32);

    // Key derivation for encryption

    // Because we are using hardened derivation, for each
    // contract we will need someone to sign it off chain

    mapping(bytes32 => bytes) internal _derivedPub;

    function onchain_DeriveKey(
        address a,
        bytes memory dPub,
        // Signature from a valid kettle
        bytes memory sig,
        uint32 index
    ) public {
        bytes32 digest = keccak256(abi.encodePacked(a, index, dPub));
        require(Secp256k1.verify(xPub, digest, sig));
        bytes32 key = keccak256(abi.encodePacked(a, index));
        _derivedPub[key] = dPub;
    }

    function offchain_DeriveKey(address a, uint32 index) public returns (bytes memory dPub, bytes memory sig) {
        bytes32 dPriv = _derivedPriv(a, index);
        dPub = PKE.derivePubKey(dPriv);
        bytes32 digest = keccak256(abi.encodePacked(a, index, dPub));
        sig = Secp256k1.sign(uint256(xPriv()), digest);
        require(Secp256k1.verify(xPub, digest, sig));
    }
}

contract NewKeyManager_v0 is NewKeyManagerBase {
    IAndromeda public Suave;
    BIP32 public bip32;


    constructor(address _Suave, BIP32 _bip32) {
        Suave = IAndromeda(_Suave);
        bip32 = _bip32;
    }

    function derivedPub(address a, uint32 index) public view returns (bytes memory) {
        bytes32 key = keccak256(abi.encodePacked(a, index));
        return _derivedPub[key];
    }

    function derivedPub(address a) public view returns (bytes memory) {
        bytes32 key = keccak256(abi.encodePacked(a, uint32(0)));
        return _derivedPub[key];
    }

    // Any contract in confidential mode can request a
    // hardened derived key
    function _derivedPriv(address a, uint32 index) internal override returns (bytes32) {
        bytes32 seed = Suave.volatileGet("seed");
        // derive the key pair of the address first
        uint32 addrIndex = uint32(uint256(keccak256(abi.encodePacked(a)))) | HARDENED_START_INDEX;
        (BIP32.ExtendedPrivateKey memory _xPriv, BIP32.ExtendedPublicKey memory _xPub) = bip32.deriveChildKeyPairFromSeed(abi.encodePacked(seed), addrIndex);
        // if an index is provided, derive the child key pair of the given address at that index
        if(index >= HARDENED_START_INDEX) {
            (BIP32.ExtendedPrivateKey memory _cxPriv, BIP32.ExtendedPublicKey memory _cxPub) = bip32.deriveChildKeyPair(_xPriv, index);
            return _cxPriv.key;
        }
        // if no index is provided, return the address's private key
        return _xPriv.key;
    }

    function derivedPriv() public returns (bytes32) {
        return _derivedPriv(msg.sender, 0);
    }

    function derivedPriv(uint32 index) public returns (bytes32) {
        require(index >= 0x80000000, "Can't derive hardened key from non-hardened index!");
        return _derivedPriv(msg.sender, index);
    }


    // 1. Bootstrap phase
    function offchain_Bootstrap() public returns (address _xPub, bytes memory att) {
        require(xPub == address(0));
        bytes32 seed = Suave.localRandom();
        bytes32 xPrivKey = bip32.newFromSeed(abi.encodePacked(seed)).key;
        _xPub = Secp256k1.deriveAddress(uint256(xPrivKey));
        Suave.volatileSet("seed", seed);
        att = Suave.attestSgx(keccak256(abi.encodePacked("xPub", _xPub)));
    }

    function seed() internal override returns (bytes32) {
        return Suave.volatileGet("seed");
    }

    function xPriv() internal override returns (bytes32) {
        return bip32.newFromSeed(abi.encodePacked(seed())).key;
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
        return PKE.encrypt(registry[newkettle], r, abi.encodePacked(seed()));
    }

    event Onboard(address addr, bytes ciphertext);

    function onchain_Onboard(address addr, bytes memory ciphertext) public {
        // Note: nothing guarantees all ciphertexts on chain are valid
        emit Onboard(addr, ciphertext);
    }

    function finish_Onboard(bytes memory ciphertext) public {
        bytes32 myPriv = Suave.sealingKey("myPriv");
        bytes32 seed = abi.decode(PKE.decrypt(myPriv, ciphertext), (bytes32));
        bytes32 xPriv_ = bip32.newFromSeed(abi.encodePacked(seed)).key;
        require(Secp256k1.deriveAddress(uint256(xPriv_)) == xPub);
        Suave.volatileSet("seed", seed);
    }
}
