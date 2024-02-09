pragma solidity ^0.8.13;

import "./KeyManager.sol";

contract AuthHelper {
    KeyManager_v0 private keymgr;
    address owner;

    constructor(KeyManager_v0 _keymgr) {
        keymgr = _keymgr; // Note that we only derive privkey, so we don't require derivekey be called with the address of this (private) contract. The key manager has to be bootstrapped.
        owner = msg.sender; // Can we really trust the sender though? The kettle could be spoofing it
    }

    function hashSecret() public returns (bytes32) {
        // We deploy a different contract as the derivePriv will be different in this scenario!
        require(msg.sender == owner);
        return keymgr.derivedPriv();
    }
}

contract KeyHelper {
    KeyManager_v0 private keymgr;
    AuthHelper private auth_helper;

    constructor(KeyManager_v0 _keymgr) {
        keymgr = _keymgr;
        auth_helper = new AuthHelper(_keymgr);
    }

    /*
    To initialize, some Kettle must invoke:
       `keymgr.offchain_DeriveKey(auc) -> dPub,v,r,s`
       `keymgr.onchain_DeriveKey(auc,dPub,v,r,s)`
    */
    function isInitialized() public view returns (bool) {
        return pubkey().length != 0;
    }
    function pubkey() public view returns (bytes memory) {
        return keymgr.derivedPub(address(this));
    }
    function privkey() private returns (bytes32) {
        return keymgr.derivedPriv();
    }
    function hashSecret() private returns (bytes32) {
        return auth_helper.hashSecret();
    }

    function encrypt(bytes memory message, bytes32 r) internal view returns (bytes memory) {
        return PKE.encrypt(pubkey(), r, message);
    }
    function encrypt(string memory message, bytes32 r) internal view returns (string memory) {
        return string(encrypt(abi.encodePacked(message), r));
    }
    function encrypt(bytes memory message) internal view returns (bytes memory) {
        return encrypt(message, keymgr.Suave().localRandom());
    }
    function encrypt(string memory message) internal view returns (string memory) {
        return string(encrypt(abi.encodePacked(message), keymgr.Suave().localRandom()));
    }

    function decrypt(bytes memory ciphertext) internal returns (bytes memory message) {
        // Note that it's possible to decrypt an auth_encrypted message
        return PKE.decrypt(privkey(), ciphertext);
    }

    function auth_encrypt(bytes memory message, bytes32 r) internal returns (bytes memory) {
        bytes memory ciphertext = PKE.encrypt(pubkey(), r, message);
        // !!!! We should be using a different key for the hash! Coming soon once we have key derivation
        return abi.encode(ciphertext, keccak256(abi.encodePacked(hashSecret(), ciphertext)));
    }
    function auth_encrypt(string memory message, bytes32 r) internal view returns (string memory) {
        return string(encrypt(abi.encodePacked(message), r));
    }
    function auth_encrypt(bytes memory message) internal view returns (bytes memory) {
        return encrypt(message, keymgr.Suave().localRandom());
    }
    function auth_encrypt(string memory message) internal view returns (string memory) {
        return string(encrypt(abi.encodePacked(message), keymgr.Suave().localRandom()));
    }

    function auth_decrypt(bytes memory message) internal returns (bool, bytes memory) {
        (bytes memory ciphertext, bytes32 hash) = abi.decode(message, (bytes, bytes32));
        bool auth_ok = hash == keccak256(abi.encodePacked(hashSecret(), ciphertext));
        if (!auth_ok) {
            return (false, "");
        }
        return (true, PKE.decrypt(privkey(), ciphertext));
    }
}

