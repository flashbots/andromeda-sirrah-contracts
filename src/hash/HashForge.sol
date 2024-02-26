// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {IHash} from "src/hash/IHash.sol";

interface Vm {
    function ffi(string[] calldata commandInput) external view returns (bytes memory result);
}

contract HashForge is IHash {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function sha512(bytes memory data) external view override returns (bytes memory) {
        require(data.length > 0, "sha512: data length must be greater than 0");
        string[] memory inputs = new string[](3);
        inputs[0] = "sh";
        inputs[1] = "ffi/sha512.sh";
        inputs[2] = string(data);
        return vm.ffi(inputs);
    }
}