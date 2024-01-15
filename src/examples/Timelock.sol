pragma solidity ^0.8.13;

import "../crypto/secp256k1.sol";
import "../crypto/encryption.sol";
import "../KeyManager.sol";

contract Timelock {
    KeyManager_v0 keymgr;
    constructor(KeyManager_v0 _keymgr) {
        keymgr = _keymgr;
    }

    // Dumb workaround because we don't have the block environment yet
    uint public blocknumber;
    function number() public view returns(uint) {
	if (block.number > blocknumber) return block.number;
	return blocknumber;
    }
    function advance() public { blocknumber = block.number; }

    /*
    To initialize, some Kettle must invoke:
       `keymgr.offchain_DeriveKey(auc) -> dPub,v,r,s`
       `keymgr.onchain_DeriveKey(auc,dPub,v,r,s)`
    */
    function isInitialized() public view returns (bool) {
        return keymgr.derivedPub(address(this)).length != 0;
    }
    
    // Mapping from ciphertext to release date
    mapping (bytes32 => uint) public deadlines;
    event EncryptedMessage(bytes ciphertext, bytes32 contentHash, uint deadline);

    // Helper function for a client to run locally
    function encryptMessage(string memory message, bytes32 r) public view returns (bytes memory) {
        return PKE.encrypt(keymgr.derivedPub(address(this)), r,
			   abi.encodePacked(message));
    }

    // Post an encrypted message
    uint constant DELAY_BLOCKS = 15; // Wait 15 blocks ~1minute
    function submitEncrypted(bytes memory ciphertext) public {
	bytes32 contentHash = keccak256(ciphertext);
	deadlines[contentHash] = block.number + DELAY_BLOCKS;
        emit EncryptedMessage(ciphertext, contentHash, deadlines[contentHash]);
    }

    // Decrypt the message if the block height is high enough
    function decrypt(bytes memory ciphertext) public returns (bytes memory message) {
	bytes32 contentHash = keccak256(ciphertext);
	require(deadlines[contentHash] != 0);
	require(number() >= deadlines[contentHash]);
	return PKE.decrypt(keymgr.derivedPriv(), ciphertext);
    }
}
