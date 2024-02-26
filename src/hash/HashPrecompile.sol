// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {IHash} from "src/hash/IHash.sol";

contract HashPrecompile is IHash {
    // The address of the SHA512 precompile 
    address public constant SHA512_ADDR = 0x0000000000000000000000000000000000050700;

    function sha512(bytes memory data) external view override returns (bytes memory) {
        require(data.length > 0, "sha512: data length must be greater than 0");
        (bool success, bytes memory output) = SHA512_ADDR.staticcall(data);
        require(success);
        require(output.length == 64);
        return output;
    }
}