// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

interface IHash {
    function sha512(bytes memory data) external view returns (bytes memory);
}
