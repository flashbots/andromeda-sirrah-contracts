pragma solidity ^0.8.13;

import "../crypto/secp256k1.sol";
import "../crypto/encryption.sol";
import "../KeyManager.sol";

contract HTTP {
    address public constant DO_HTTP_REQUEST = 0x0000000000000000000000000000000043200002;

    function makeHttpCall() public returns (string memory) {
        HttpRequest memory request;
        request.url = "https://status.flashbots.net/summary.json";
        request.method = "GET";
        return string(doHTTPRequest(request));
    }

    // from suave-std
    struct HttpRequest {
        string url;
        string method;
        string[] headers;
        bytes body;
        bool withFlashbotsSignature;
    }

    function doHTTPRequest(HttpRequest memory request) internal returns (bytes memory) {
        (bool success, bytes memory data) = DO_HTTP_REQUEST.call(abi.encode(request));
        require(success);
        return abi.decode(data, (bytes));
    }
}
