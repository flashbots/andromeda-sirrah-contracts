// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

interface ICrypto {
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
    function sha512(bytes memory data) external view returns (bytes memory);
    function derivePubKey(ExtendedPrivateKey memory xPriv) external view returns (ExtendedPublicKey memory xPub);
    function newFromSeed(bytes memory seed) external view returns (ExtendedPrivateKey memory);
    function derivePubKeyFromParentPubKey(ExtendedPublicKey memory parent, uint32 index) external view returns (ExtendedPublicKey memory xPub);
    function deriveChildKeyPairFromSeed(bytes memory seed, uint32 index) external view returns (ExtendedPrivateKey memory xPriv, ExtendedPublicKey memory xPub);
    function deriveChildKeyPairFromPath(bytes memory seed, string memory path) external view returns (ExtendedPrivateKey memory xPriv, ExtendedPublicKey memory xPub);
}