pragma solidity ^0.8.13;

import "../crypto/secp256k1.sol";
import "../crypto/encryption.sol";
import "../KeyManager.sol";

contract HTTP {
    KeyManager_v0 keymgr;
    address public constant HTTP_ADDR = 0x0000000000000000000000000000000000040705;


    constructor(KeyManager_v0 _keymgr) {
        keymgr = _keymgr;
    }

    /*
    To initialize, some Kettle must invoke:
       `keymgr.offchain_DeriveKey(auc) -> dPub,v,r,s`
       `keymgr.onchain_DeriveKey(auc,dPub,v,r,s)`
    */
    function isInitialized() public view returns (bool) {
        return keymgr.derivedPub(address(this)).length != 0;
    }

    function makeHttpCall() public view returns (string memory) {
        return httpCall("https://scholar.google.com");
    }

    function httpCall(string memory url) internal view returns (string memory) {
        (bool success, bytes memory response) = HTTP_ADDR.staticcall(bytes(url));
        require(success);
        // return response;
        return string(response);
    }
}
