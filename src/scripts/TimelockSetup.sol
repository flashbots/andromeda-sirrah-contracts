// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {AndromedaRemote} from "src/AndromedaRemote.sol";
import {SigVerifyLib} from "automata-dcap-v3-attestation/utils/SigVerifyLib.sol";
import {KeyManager_v0} from "src/KeyManager.sol";

contract TimelockSetup is Script {
    function run() public {
        console2.log("Running TimelockSetup");
        SigVerifyLib lib = SigVerifyLib(vm.envAddress("sigVerifyLib"));
        AndromedaRemote andromeda = AndromedaRemote(vm.envAddress("andromeda"));
        console2.log("andromeda=%s", address(andromeda));
        andromeda.initialize();
        // vm.warp(1701528486);

        andromeda.setMrSigner(bytes32(0x93adbda6205882743aedecbbebfb4bae7f132a9bbbeac9497fcd3c140dffe52c), true);
    }
}

// run this with a different private key if needed
contract TimelockSetup2 is Script {
    function run() public {
        console2.log("Running TimelockSetup2");
        // To ensure we don't use the same address with volatile storage
        // vm.prank(vm.addr(uint256(keccak256("examples/Timelock.t.sol"))));
        KeyManager_v0 keymgr = new KeyManager_v0(
            address(vm.envAddress("andromeda"))
        );
        (address xPub, bytes memory att) = keymgr.offchain_Bootstrap();
        keymgr.onchain_Bootstrap(xPub, att);
    }
}
