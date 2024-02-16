// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {ICrypto} from "src/ICrypto.sol";

contract BIP32 is ICrypto {
    struct ExtendedKeyAttributes {
        // Depth in the key derivation heirarchy
        uint8 depth;
        uint32 parentFingerprint;
        // Index of the key in the parent's children
        uint32 childNumber;
        bytes32 chainCode;
    }
    struct ExtendedKey {
        bytes32 key;
        ExtendedKeyAttributes attributes;
    }
    
    // Derivation domain separator for BIP39 keys array 
    bytes public constant BIP32_DERIVATION_DOMAIN = hex"426974636f696e2073656564";
    
    // The address of the SHA512 precompile 
    address public constant SHA512_ADDR = 0x0000000000000000000000000000000000050700;

    function sha512(bytes memory data) external view returns (bytes memory) {
        require(data.length > 0, "Andromeda: data length must be greater than 0");
        (bool success, bytes memory output) = SHA512_ADDR.staticcall(data);
        require(success);
        require(output.length == 64);
        return output;
    }

    function split(bytes memory data) internal view returns(bytes32 key, bytes32 chain_code) {
        bytes memory digest = this.sha512(data);    
        assembly {
        key := mload(add(digest, 32)) // Load first 32 bytes
        chain_code := mload(add(digest, 64)) // Load second 32 bytes
        }
    }

    // This will be applied on the parent public key when generating the child pub/priv key
    function fingerprint(bytes32 key) internal pure returns (uint32) {
        bytes32 digest = ripemd160(abi.encodePacked(keccak256(abi.encodePacked(key))));
        // return the first 4 bytes of the digest as a uint32
        return uint32(uint256(digest) >> 224);
    }

    // Based on the context, it generates either the extended private key or extended public key
    function newFromSeed(bytes memory seed) internal view returns (ExtendedKey memory) {
        // if seed length is not 16 32 or 64 bytes, throw
        require(seed.length == 16 || seed.length == 32 || seed.length == 64, "Andromeda: seed length must be 16, 32 or 64 bytes");
        bytes memory output = this.sha512(abi.encodePacked(BIP32_DERIVATION_DOMAIN, seed));
        (bytes32 secret_key, bytes32 chain_code) = split(output);
        return ExtendedKey(secret_key, ExtendedKeyAttributes(0, 0, 0, chain_code));
    }

}