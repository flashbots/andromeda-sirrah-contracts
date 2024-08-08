pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";

import {Secp256k1} from "src/crypto/secp256k1.sol";
import {PKE} from "src/crypto/encryption.sol";

import {IAndromeda} from "src/IAndromeda.sol";
import {AndromedaForge} from "src/AndromedaForge.sol";

import {BIP32} from "../src/BIP32.sol";
import {KeyManager_v0} from "src/KeyManager.sol";

import {VersionGadget} from "src/gadgets/VersionGadget.sol";
import {AttestationGadget} from "src/gadgets/AttestationGadget.sol";
import {CensorshipResistanceGadget} from "src/gadgets/CensorshipResistanceGadget.sol";
import {encrypted_bytes, EncryptedInputsGadget, KeyManager} from "src/gadgets/EncryptedInputsGadget.sol";
import {AuthGadget} from "src/gadgets/AuthGadget.sol";
import {KillswitchGadget} from "src/gadgets/KillswitchGadget.sol";

import {SirrahSecretsManagerBase} from "src/SecretsManagerBase.sol";
import {SirrahSecretsManager_V0, BIP32KeyManager} from "src/SecretsManager.sol";

contract SirrahSecretsManager_Test is Test {
    AndromedaForge public andromeda;
    SirrahSecretsManagerBase testContract;

    function setUp() public {
        andromeda = new AndromedaForge();

        KeyManager_v0 keymanager = new KeyManager_v0(address(andromeda));

        (address _xPub, bytes memory att) = keymanager.offchain_Bootstrap();
        keymanager.onchain_Bootstrap(_xPub, att);

        testContract = new SirrahSecretsManager_V0(andromeda, new BIP32KeyManager(andromeda, keymanager));
    }

    function testSecretsManagerSanity() public {}
}
