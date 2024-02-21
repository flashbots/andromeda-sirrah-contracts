// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {ICrypto} from "src/ICrypto.sol";
import {PKE} from "../src/crypto/encryption.sol";
import {Utils} from "src/utils/Utils.sol";

interface Vm {
    function ffi(string[] calldata commandInput) external view returns (bytes memory result);
}

contract BIP32Forge is ICrypto {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    // Derivation domain separator for BIP39 keys array 
    bytes public constant BIP32_DERIVATION_DOMAIN = hex"426974636f696e2073656564";

    function sha512(bytes memory data) external view override returns (bytes memory) {
        require(data.length > 0, "sha512: data length must be greater than 0");
        string[] memory inputs = new string[](3);
        inputs[0] = "sh";
        inputs[1] = "ffi/sha512.sh";
        inputs[2] = string(data);
        return vm.ffi(inputs);
    }

    function localRandom() public view returns (bytes32) {
        string[] memory inputs = new string[](2);
        inputs[0] = "sh";
        inputs[1] = "ffi/local_random.sh";
        bytes memory res = vm.ffi(inputs);
        return bytes32(res);
    }

    function split(bytes memory data) public view returns(bytes32 key, bytes32 chain_code) {
        assembly {
        key := mload(add(data, 32)) // Load first 32 bytes
        chain_code := mload(add(data, 64)) // Load second 32 bytes
        }
    }


    // This will be applied on the parent public key when generating the child pub/priv key
    function fingerprint(bytes memory key) public pure returns (uint32) {
        bytes32 digest = ripemd160(abi.encodePacked(keccak256(abi.encodePacked(key))));
        // return the first 4 bytes of the digest as a uint32
        return uint32(uint256(digest) >> 224);
    }

    // Based on the context, it generates either the extended private key or extended public key
    function newFromSeed(bytes memory seed) public view override returns (ExtendedPrivateKey memory) {
        // if seed length is not 16 32 or 64 bytes, throw
        require(seed.length == 16 || seed.length == 32 || seed.length == 64, "BIP32: seed length must be 16, 32 or 64 bytes");
        bytes memory output = this.sha512(abi.encodePacked(Utils.bytesToHexString(abi.encodePacked(BIP32_DERIVATION_DOMAIN, seed))));
        (bytes32 secret_key, bytes32 chain_code) = split(output);
        return ExtendedPrivateKey(secret_key, ExtendedKeyAttributes(0, 0, 0, chain_code));
    }

    // derive extended child key pair from a parent seed
    function deriveChildKeyPairFromSeed(bytes memory seed, uint32 index) external view returns (ExtendedPrivateKey memory xPriv, ExtendedPublicKey memory xPub) {
        ExtendedPrivateKey memory parent = newFromSeed(seed);
        return deriveChildKeyPair(parent, index);
    }

    // derive extended child key pair from a parent extended private key
    function deriveChildKeyPair(ExtendedPrivateKey memory parent, uint32 index) public view returns (ExtendedPrivateKey memory xPriv, ExtendedPublicKey memory xPub) {
        // hardened key derivation if index > 0x80000000
        if (index >= 0x80000000) {
            bytes memory data = abi.encodePacked(hex"00", parent.key, index);
            bytes memory output = this.sha512(abi.encodePacked(Utils.bytesToHexString(abi.encodePacked(parent.attributes.chainCode, data))));
            (bytes32 secret_key, bytes32 chain_code) = split(output);
            ExtendedKeyAttributes memory extKeyAttr = ExtendedKeyAttributes(parent.attributes.depth + 1, fingerprint(abi.encodePacked(parent.key)), index, chain_code);
            xPriv =  ExtendedPrivateKey(secret_key, extKeyAttr);
            xPub = ExtendedPublicKey(PKE.derivePubKey(secret_key), extKeyAttr);
            
        } else {
            bytes memory data = abi.encodePacked(PKE.derivePubKey(parent.key), index);
            bytes memory output = this.sha512(abi.encodePacked(Utils.bytesToHexString(abi.encodePacked(parent.attributes.chainCode, data))));
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
        // if the path is just "m" or "M", return the extended private key and extended public key
        if(pathBytes.length <= 2) {
            return (data, ExtendedPublicKey(PKE.derivePubKey(data.key), data.attributes));
        }
        
        uint32 index = 0;
        
        // iterate through the path and derive the child key pair at each level and check the occurrence of ' to define hardened derivation or not
        for (uint i = 2; i < pathBytes.length; i++) {
            if (pathBytes[i] == bytes1('\'')) {
                //check if index + 2147483648 does not exceed uint32 max value
                require(index <= 2147483647, "BIP32: invalid path");
                index += 2147483648;
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
        
        (xPriv, xPub) = deriveChildKeyPair(data, index);
    }

    // derive child public key from a parent public key
    function derivePubKeyFromParentPubKey(ExtendedPublicKey memory parent, uint32 index) external view returns (ExtendedPublicKey memory xPub) {
        require(index < 0x80000000, "BIP32: can't derive hardened public keys from a parent public key");
        bytes memory data = abi.encodePacked(parent.key, index);
        bytes memory output = this.sha512(abi.encodePacked(Utils.bytesToHexString(abi.encodePacked(parent.attributes.chainCode, data))));
        (bytes32 secret_key, bytes32 chain_code) = split(output);
        ExtendedKeyAttributes memory extKeyAttr = ExtendedKeyAttributes(parent.attributes.depth + 1, fingerprint(parent.key), index, chain_code);
        xPub = ExtendedPublicKey(PKE.derivePubKey(secret_key), extKeyAttr);
    }

    // derive public key from a given private key
    function derivePubKey(ExtendedPrivateKey memory xPriv) external view returns (ExtendedPublicKey memory xPub) {
        return ExtendedPublicKey(PKE.derivePubKey(xPriv.key), xPriv.attributes);
    }
}