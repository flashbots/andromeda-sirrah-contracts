// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import "solidity-stringutils/strings.sol";
import {IHash} from "src/hash/IHash.sol";

interface IAndromeda is IHash {
    function attestSgx(bytes32 appData) external returns (bytes memory);
    function verifySgx(address caller, bytes32 appData, bytes memory att) external view returns (bool);
    function volatileSet(bytes32 tag, bytes32 value) external;
    function volatileGet(bytes32 tag) external returns (bytes32);
    function localRandom() external view returns (bytes32);
    function sealingKey(bytes32 tag) external view returns (bytes32);

    struct HttpRequest {
        string url;
        string method;
        string[] headers;
        bytes body;
        bool withFlashbotsSignature;
    }
    function doHTTPRequest(HttpRequest memory request) external returns (bytes memory);
}
