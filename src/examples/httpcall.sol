pragma solidity ^0.8.13;

import "../crypto/secp256k1.sol";
import "../crypto/encryption.sol";
import "../KeyManager.sol";

contract HTTP {
    KeyManager_v0 keymgr;
    address public constant DO_HTTP_REQUEST = 0x0000000000000000000000000000000043200002;


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
        HttpRequest memory request;
        request.url = "https://scholar.google.com";
        request.method = "GET";
        return doHTTPRequest(req);
    }

    // from suave-std
    struct HttpRequest {
        string url;
        string method;
        string[] headers;
        bytes body;
        bool withFlashbotsSignature;
    }

    function doHTTPRequest(HttpRequest memory request) public returns (bytes memory) {
        (bool success, bytes memory data) = DO_HTTP_REQUEST.call(abi.encode(request));
        require(success);
        return abi.decode(data, (bytes));
    }
}
