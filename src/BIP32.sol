// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {ICrypto} from "src/ICrypto.sol";
import {PKE} from "../src/crypto/encryption.sol";

contract BIP32 is ICrypto {
    struct ExtendedKeyAttributes {
        // Depth in the key derivation heirarchy
        uint8 depth;
        uint32 parentFingerprint;
        // Index of the key in the parent's children
        uint32 childNumber;
        bytes32 chainCode;
    }
    struct ExtendedPrivateKey {
        bytes32 key;
        ExtendedKeyAttributes attributes;
    }
    struct ExtendedPublicKey {
        bytes key;
        ExtendedKeyAttributes attributes;
    }
    
    // The master extended private keys
    /*ExtendedPrivateKey private xPriv;
    ExtendedPublicKey public xPub;

    constructor (bytes memory seed) {
        xPriv = newFromSeed(seed);
        xPub = ExtendedPublicKey(PKE.derivePubKey(xPriv.key), xPriv.attributes);
    }

    // get master public key
    function getMasterPub() external view returns (bytes memory) {
        return PKE.derivePubKey(xPriv.key);
    }
    */

    // Derivation domain separator for BIP39 keys array 
    bytes public constant BIP32_DERIVATION_DOMAIN = hex"426974636f696e2073656564";
    
    // The address of the SHA512 precompile 
    address public constant SHA512_ADDR = 0x0000000000000000000000000000000000050700;

    function sha512(bytes memory data) external view returns (bytes memory) {
        require(data.length > 0, "sha512: data length must be greater than 0");
        (bool success, bytes memory output) = SHA512_ADDR.staticcall(data);
        require(success);
        require(output.length == 64);
        return output;
    }

    function split(bytes memory data) internal view returns(bytes32 key, bytes32 chain_code) {
        assembly {
        key := mload(add(data, 32)) // Load first 32 bytes
        chain_code := mload(add(data, 64)) // Load second 32 bytes
        }
    }


    // This will be applied on the parent public key when generating the child pub/priv key
    function fingerprint(bytes memory key) internal pure returns (uint32) {
        bytes32 digest = ripemd160(abi.encodePacked(keccak256(abi.encodePacked(key))));
        // return the first 4 bytes of the digest as a uint32
        return uint32(uint256(digest) >> 224);
    }

    // Based on the context, it generates either the extended private key or extended public key
    function newFromSeed(bytes memory seed) internal view returns (ExtendedPrivateKey memory) {
        // if seed length is not 16 32 or 64 bytes, throw
        require(seed.length == 16 || seed.length == 32 || seed.length == 64, "BIP32: seed length must be 16, 32 or 64 bytes");
        bytes memory output = this.sha512(abi.encodePacked(BIP32_DERIVATION_DOMAIN, seed));
        (bytes32 secret_key, bytes32 chain_code) = split(output);
        return ExtendedPrivateKey(secret_key, ExtendedKeyAttributes(0, 0, 0, chain_code));
    }

    // derive extended child key pair from a parent seed
    function deriveChildKeyPairFromSeed(bytes memory seed, uint32 index) public view returns (ExtendedPrivateKey memory xPriv, ExtendedPublicKey memory xPub) {
        ExtendedPrivateKey memory parent = newFromSeed(seed);
        return deriveChildKeyPair(parent, index);
    }

    // derive extended child key pair from a parent extended private key
    function deriveChildKeyPair(ExtendedPrivateKey memory parent, uint32 index) internal view returns (ExtendedPrivateKey memory xPriv, ExtendedPublicKey memory xPub) {
        // hardened key derivation if index > 0x80000000
        if (index >= 0x80000000) {
            bytes memory data = abi.encodePacked(hex"00", parent.key, index);
            bytes memory output = this.sha512(abi.encodePacked(parent.attributes.chainCode, data));
            (bytes32 secret_key, bytes32 chain_code) = split(output);
            ExtendedKeyAttributes memory extKeyAttr = ExtendedKeyAttributes(parent.attributes.depth + 1, fingerprint(abi.encodePacked(parent.key)), index, chain_code);
            xPriv =  ExtendedPrivateKey(secret_key, extKeyAttr);
            xPub = ExtendedPublicKey(PKE.derivePubKey(secret_key), extKeyAttr);
            
        } else {
            bytes memory data = abi.encodePacked(parent.key, index);
            bytes memory output = this.sha512(abi.encodePacked(parent.attributes.chainCode, data));
            (bytes32 secret_key, bytes32 chain_code) = split(output);
            ExtendedKeyAttributes memory extKeyAttr = ExtendedKeyAttributes(parent.attributes.depth + 1, fingerprint(PKE.derivePubKey(parent.key)), index, chain_code);
            xPriv =  ExtendedPrivateKey(secret_key, extKeyAttr);
            xPub = ExtendedPublicKey(PKE.derivePubKey(secret_key), extKeyAttr);
        }
    }


    // derive child extended key pairs from a given string path
    function deriveChildKeyPairFromPath(bytes memory seed, string memory path) external view returns (ExtendedPrivateKey memory xPriv, ExtendedPublicKey memory xPub) {
        bytes memory pathBytes = bytes(path);
        // require that the path is not empty and the first character of the path is "m" or "M"
        require(pathBytes.length > 0 || pathBytes[0] == bytes1('m') || pathBytes[0] == bytes1('M'), "BIP32: invalid path");
        ExtendedPrivateKey memory data = newFromSeed(seed);
        uint32 index = 0;
        
        // iterate through the path and derive the child key pair at each level and check the occurrence of ' to define hardened derivation or not
        for (uint i = 2; i < pathBytes.length; i++) {
            if (pathBytes[i] == bytes1('\'')) {
                (xPriv, xPub) = deriveChildKeyPair(data, index + 0x80000000);
            } else if (pathBytes[i] == bytes1('/')) {
                (xPriv, xPub) = deriveChildKeyPair(data, index);
                data = xPriv;
                index = 0;
            } else {
                // check if the character is not a number and throw instead of converting it to a number
                require(uint8(pathBytes[i]) >= 48 && uint8(pathBytes[i]) <= 57, "BIP32: invalid path");
                index = index * 10 + uint32(uint8(pathBytes[i]) - 48);
                
                // TODO further formating checks are probably needed to avoid invalid formats, such as m/000123 or m/' or m/1'' or m// etc...
            }
        }

        // in case the last character of the path is not a ' or /
        if(pathBytes[pathBytes.length - 1] != bytes1('\'')) {
            (xPriv, xPub) = deriveChildKeyPair(data, index);
        }
    }
}