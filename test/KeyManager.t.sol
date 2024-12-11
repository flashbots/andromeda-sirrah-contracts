// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {KeyManager_v0, KeyManager_v1_Upgradeable, KeyManagerBase} from "../src/KeyManager.sol";
import {KeyHelper} from "../src/KeyHelper.sol";
import {PKE} from "../src/crypto/encryption.sol";
import {AndromedaForge} from "src/AndromedaForge.sol";
import "forge-std/Vm.sol";

contract KeyManager_v0_Test is Test {
    AndromedaForge andromeda;
    KeyManager_v0 keymgr;

    Vm.Wallet alice;
    Vm.Wallet bob;
    Vm.Wallet carol;

    function setUp() public {
        andromeda = new AndromedaForge();
        vm.prank(vm.addr(uint(keccak256("KeyManager.t.sol"))));
        keymgr = new KeyManager_v0(address(andromeda));

        alice = vm.createWallet("alice");
        bob = vm.createWallet("bob");
    }

    function testKeyManager() public {
        // 1. Bootstrap
        // 1a. Offchain generate the key
        andromeda.switchHost("alice");
        (address xPub, bytes memory att) = keymgr.offchain_Bootstrap();
        // 1b. Post the key and attestation on-chain
        keymgr.onchain_Bootstrap(xPub, att);

        // 2. Register a new node
        // 2a. Offchain generate a register request
        andromeda.switchHost("bob");
        (address bob_kettle, bytes memory bPub, bytes memory attB) = keymgr
            .offchain_Register();
        // 2b. Onchain submit the request
        keymgr.onchain_Register(bob_kettle, bPub, attB);

        // 2.1 Register a new node
        // 2.1a. Offchain generate a register request
        andromeda.switchHost("charlie");
        (address charlie_kettle, bytes memory cPub, bytes memory attC) = keymgr
            .offchain_Register();
        // 2.1b. Onchain submit the request
        keymgr.onchain_Register(charlie_kettle, cPub, attC);

        assert(bob_kettle != charlie_kettle);

        // 3. Help onboard a new node
        // 3a. Offchain generate a ciphertext with the key
        andromeda.switchHost("alice");
        bytes memory ciphertext = keymgr.offchain_Onboard(bob_kettle);
        // 3b. Onchain post the ciphertext
        keymgr.onchain_Onboard(bob_kettle, ciphertext);
        // 3c. Load the data received
        andromeda.switchHost("bob");
        keymgr.finish_Onboard(ciphertext);

        // 3.1. Help onboard a second node
        ciphertext = keymgr.offchain_Onboard(charlie_kettle);
        // 3.1b. Onchain post the ciphertext
        keymgr.onchain_Onboard(charlie_kettle, ciphertext);
        // 3.1c. Load the data received
        andromeda.switchHost("charlie");
        keymgr.finish_Onboard(ciphertext);
    }

    function testDerived() public {
        // Do the bootstrap
        (address xPub, bytes memory att) = keymgr.offchain_Bootstrap();
        keymgr.onchain_Bootstrap(xPub, att);

        // Show the derived key associated with this contract.
        (bytes memory dPub, bytes memory sig) = keymgr.offchain_DeriveKey(
            address(this)
        );
        keymgr.onchain_DeriveKey(address(this), dPub, sig);

        bytes32 dPriv = keymgr.derivedPriv();
        assertEq(PKE.derivePubKey(dPriv), keymgr.derivedPub(address(this)));
    }
}

contract KeyHelperContract is KeyHelper {

    constructor(KeyManagerBase keymgr) KeyHelper(keymgr) {}

    function auth_encrypt_(bytes memory message) public returns (bytes memory) {
        return auth_encrypt(message);
    }

    function encrypt_(bytes memory message) public returns (bytes memory) {
        return encrypt(message);
    }

    function auth_decrypt_(bytes memory message) public returns (bool, bytes memory) {
        return auth_decrypt(message);
    }

    function decrypt_(bytes memory message) public returns (bytes memory) {
        return decrypt(message);
    }
}

contract KeyManager_v1_Test is Test {
    AndromedaForge andromeda;
    KeyManager_v1_Upgradeable keymgr;
    KeyHelperContract keyhlpr;
    mapping(string => address) public kettles;
    string private bootstrap_user;
    string private onboard_user;

    function setUp() public {
        vm.prank(vm.addr(uint(keccak256("KeyManager_v1.t.sol"))));

        andromeda = new AndromedaForge();
        keymgr = new KeyManager_v1_Upgradeable(address(andromeda), bytes32(0x1cf2e52911410fbf3f199056a98d58795a559a2e800933f7fcd13d048462271c));
        keyhlpr = new KeyHelperContract(keymgr);
        bootstrap("0_alice");
        address bob_kettle = onboardUser("0_bob");
        address charlie_kettle = onboardUser("0_charlie");
        assert(bob_kettle != charlie_kettle);
        deriveKey(address(keyhlpr));
    }

    function bootstrap(string memory hostname) private {
        // 1. Bootstrap
        // 1a. Offchain generate the key
        andromeda.switchHost(hostname);
        (address xPub, bytes memory att) = keymgr.offchain_Bootstrap();
        // 1b. Post the key and attestation on-chain
        keymgr.onchain_Bootstrap(xPub, att);
        bootstrap_user = hostname;
        onboardUser(hostname);
    }

    function onboardUser(string memory newhost) private returns (address) {
        // 2. Register a new node
        // 2a. Offchain generate a register request
        andromeda.switchHost(newhost);
        (address kettle_addr, bytes memory bPub, bytes memory attB) = keymgr
            .offchain_Register();
        if (kettles[newhost] != address(0)) {
            assert(kettles[newhost] == kettle_addr);
        }
        kettles[newhost] = kettle_addr;
        // 2b. Onchain submit the request
        keymgr.onchain_Register(kettle_addr, bPub, attB);

        // 3. Help onboard a new node
        // 3a. Offchain generate a ciphertext with the key
        andromeda.switchHost(bootstrap_user);
        bytes memory ciphertext = keymgr.offchain_Onboard(kettle_addr);
        // 3b. Onchain post the ciphertext
        keymgr.onchain_Onboard(kettle_addr, ciphertext);
        // 3c. Load the data received
        andromeda.switchHost(newhost);
        keymgr.finish_Onboard(ciphertext);
        onboard_user = newhost;
        return kettle_addr;
    }

    function deriveKey(address contractAddr) private {
        andromeda.switchHost(bootstrap_user);
        (bytes memory dPub, bytes memory sig) = keymgr.offchain_DeriveKey(
            contractAddr
        );
        keymgr.onchain_DeriveKey(contractAddr, dPub, sig);
    }

    function testOnboardAfterUpgrade() public {
        string memory prev_bootstrap_user = bootstrap_user;
        string memory prev_onboard_user = onboard_user;
        // owner changes mrenclave
        andromeda.switchHost("default");
        keymgr.approvedNewMRenclave(bytes32(0xed24ce78cd65438dc3b74e549b1ad5c591dba88e2078e676fca600ebbec21370));

        // bootstrap new public key
        andromeda.switchHost("1_alice");
        bootstrap("1_alice");

        // test register enclave with wrong mrenclave (i.e. previous version's mrenclave)
        andromeda.switchHost(prev_onboard_user);
        (address kettle_addr0, bytes memory pub0, bytes memory att0) = keymgr
            .offchain_Register();
        assert(kettles[prev_onboard_user] == kettle_addr0);
        vm.expectRevert("mrenclave does not match");
        keymgr.onchain_Register(kettle_addr0, pub0, att0);

        // test register new enclave bootstrapped from old version enclave
        andromeda.switchHost("1_bob");
        (address bob1_kettle_addr, bytes memory bob1_Pub, bytes memory bob1_attB) = keymgr
            .offchain_Register();
        keymgr.onchain_Register(bob1_kettle_addr, bob1_Pub, bob1_attB);
        andromeda.switchHost(prev_bootstrap_user);
        bytes memory bob1_ciphertext_0 = keymgr.offchain_Onboard(bob1_kettle_addr);
        keymgr.onchain_Onboard(bob1_kettle_addr, bob1_ciphertext_0);
        andromeda.switchHost("1_bob");
        vm.expectRevert("private key wrong");
        keymgr.finish_Onboard(bob1_ciphertext_0);

        // test register new enclave bootstrapped from old version enclave
        andromeda.switchHost(prev_onboard_user);
        bytes memory bob1_ciphertext_1 = keymgr.offchain_Onboard(bob1_kettle_addr);
        keymgr.onchain_Onboard(bob1_kettle_addr, bob1_ciphertext_1);
        andromeda.switchHost("1_bob");
        vm.expectRevert("private key wrong");
        keymgr.finish_Onboard(bob1_ciphertext_1);

        // register with latest version
        andromeda.switchHost("1_alice");
        bytes memory bob1_ciphertext_2 = keymgr.offchain_Onboard(bob1_kettle_addr);
        keymgr.onchain_Onboard(bob1_kettle_addr, bob1_ciphertext_2);
        andromeda.switchHost("1_bob");
        keymgr.finish_Onboard(bob1_ciphertext_2);
    }


    function testEncryptionAfterUpgrade() public {
        andromeda.switchHost(bootstrap_user);
        bytes memory pt1 = bytes("12345678123456781234567812345678");
        bytes memory ct1_auth = keyhlpr.auth_encrypt_(pt1);
        bytes memory ct1_encr = keyhlpr.encrypt_(pt1);
        bytes memory ret1_auth;
        bool res1_auth;
        (res1_auth, ret1_auth) = keyhlpr.auth_decrypt_(ct1_auth);
        assert(res1_auth);
        assertEq(ret1_auth, pt1);
        assertEq(keyhlpr.decrypt_(ct1_encr), pt1);

        // owner changes mrenclave
        andromeda.switchHost("default");
        keymgr.approvedNewMRenclave(bytes32(0xfd24ce78cd65438dc3b74e549b1ad5c591dba88e2078e676fca600ebbec21370));
        // bootstrap new public key
        bootstrap("2_alice");
        onboardUser("2_bob");
        andromeda.switchHost("2_bob");

        // new version should not be able to decrypt tag of old version
        bytes memory ret2_auth;
        bool res2_auth;
        (res2_auth, ret2_auth) = keyhlpr.auth_decrypt_(ct1_auth);
        assertFalse(res2_auth);
        assertNotEq(keccak256(ret2_auth), keccak256(pt1));
        vm.expectRevert("Invalid tag, decryption failed");
        keyhlpr.decrypt_(ct1_encr);

        deriveKey(address(keyhlpr));
        // new version should still not be able to decrypt tag of old version after key derivation
        bytes memory ret3_auth;
        bool res3_auth;
        (res3_auth, ret3_auth) = keyhlpr.auth_decrypt_(ct1_auth);
        assertFalse(res3_auth);
        assertNotEq(keccak256(ret3_auth), keccak256(pt1));
        vm.expectRevert("Invalid tag, decryption failed");
        keyhlpr.decrypt_(ct1_encr);

        // test decryption with new key
        bytes memory pt4 = bytes("12345678876543211234567887654321");
        bytes memory ct4_auth = keyhlpr.auth_encrypt_(pt4);
        bytes memory ct4_encr = keyhlpr.encrypt_(pt4);
        bytes memory ret4_auth;
        bool res4_auth;
        (res4_auth, ret4_auth) = keyhlpr.auth_decrypt_(ct4_auth);
        assert(res4_auth);
        assertEq(ret4_auth, pt4);
        assertEq(keyhlpr.decrypt_(ct4_encr), pt4);
    }

    function testDerivedAfterUpgrade() public {

        address contractAddr = address(0x7Fa9385Be102aC3eac297483DD6233d62B3e1497);

        andromeda.switchHost(bootstrap_user);
        (bytes memory dPub_0, bytes memory sig) = keymgr.offchain_DeriveKey(
            contractAddr
        );
        // new public key not derived on chain yet

        keymgr.onchain_DeriveKey(contractAddr, dPub_0, sig);

        bytes32 dPriv_0 = keymgr.derivedPriv();
        // new public key is derived on chain
        assertEq(dPub_0, keymgr.derivedPub(contractAddr));

        // owner changes mrenclave
        andromeda.switchHost("default");
        keymgr.approvedNewMRenclave(bytes32(0x0d24ce78cd65438dc3b74e549b1ad5c591dba88e2078e676fca600ebbec21370));
        // bootstrap new public key
        bootstrap("3_alice");
        onboardUser("3_bob");
        andromeda.switchHost("3_bob");

        // updated enclaves should have new master private key
        bytes32 dPriv_1 = keymgr.derivedPriv();
        assertNotEq(dPriv_0, dPriv_1);

        assertNotEq(keccak256(PKE.derivePubKey(dPriv_1)), keccak256(keymgr.derivedPub(address(this))));

        // derive new key for new enclave version
        (bytes memory dPub_1, bytes memory sig_1) = keymgr.offchain_DeriveKey(
            contractAddr
        );

        // old public key is different than new public key
        assertNotEq(keccak256(dPub_0), keccak256(dPub_1));

        // new public key not derived on chain yet
        assertNotEq(keccak256(dPub_1), keccak256(keymgr.derivedPub(contractAddr)));

        // can't use pubkey derived from old enclave
        vm.expectRevert();
        keymgr.onchain_DeriveKey(contractAddr, dPub_0, sig);

        keymgr.onchain_DeriveKey(contractAddr, dPub_1, sig_1);
        // new public key is derived on chain
        assertEq(dPub_1, keymgr.derivedPub(contractAddr));
    }
}
