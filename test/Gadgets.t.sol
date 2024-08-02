pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";

import {BIP32} from "../src/BIP32.sol";
import {Secp256k1} from "src/crypto/secp256k1.sol";
import {PKE} from "src/crypto/encryption.sol";

import {IAndromeda} from "src/IAndromeda.sol";
import {AndromedaForge} from "src/AndromedaForge.sol";

import {VersionGadget} from "src/gadgets/VersionGadget.sol";
import {AttestationGadget} from "src/gadgets/AttestationGadget.sol";
import {CensorshipResistanceGadget} from "src/gadgets/CensorshipResistanceGadget.sol";
import {encrypted_bytes, EncryptedInputsGadget, KeyManager} from "src/gadgets/EncryptedInputsGadget.sol";
import {AuthGadget} from "src/gadgets/AuthGadget.sol";
import {KillswitchGadget} from "src/gadgets/KillswitchGadget.sol";

contract AttestationTestContract is AttestationGadget {
    IAndromeda private suave;

    constructor(IAndromeda _suave) {
        suave = _suave;
    }

    function Suave() internal view virtual override returns (IAndromeda) {
        return suave;
    }

    function offchain(bytes memory input_data) public returns (bytes memory attestation) {
        return offchain_attest(this.onchain.selector, input_data);
    }

    function onchain(bytes memory input_data, bytes memory attestation)
        public
        onchain_verify(input_data, attestation)
        returns (bytes memory)
    {
        return input_data;
    }
}

contract AttestationGadget_Test is Test {
    AndromedaForge public andromeda;
    AttestationTestContract testContract;

    function setUp() public {
        andromeda = new AndromedaForge();
        testContract = new AttestationTestContract(andromeda);
    }

    bytes32 constant salt = hex"234902409284092384092384";

    function testAttestationHappyPath() public {
        /* generate an offchain attestation */
        bytes memory attestation = testContract.offchain("xoxo");

        bytes memory expectedAppData =
            abi.encodePacked(AttestationTestContract.onchain.selector, address(testContract), "xoxo");
        bytes memory expectedAttestation =
            abi.encodePacked(keccak256(abi.encode(salt, address(testContract), keccak256(expectedAppData))));
        require(keccak256(attestation) == keccak256(expectedAttestation));

        /* verify the contract accepts the attestation */
        testContract.onchain("xoxo", attestation);
    }

    function testIncorrectAttestation() public {
        bytes memory attestation = testContract.offchain("xoxo");
        /* verify the contract does not accept an incorrect attestation */
        vm.expectRevert();
        testContract.onchain("xoxo", abi.encodePacked(keccak256(attestation)));
    }

    function testIncorrectCalldataForAttestation() public {
        bytes memory attestation = testContract.offchain("xoxo");
        /* verify the contract does not accept an attestation for different user data */
        vm.expectRevert();
        testContract.onchain("xoxo2", attestation);
    }
}

contract VersionTestContract is VersionGadget {
    bytes32 public version_override;

    function set_version_override(bytes memory _ov) public returns (bytes32) {
        version_override = keccak256(_ov);
        return version_override;
    }

    function clr_version_override() public returns (bytes32) {
        version_override = bytes32(0);
        return current_version();
    }

    function current_version() public virtual override returns (bytes32) {
        if (version_override != bytes32(0)) {
            return version_override;
        }
        return keccak256(abi.encodePacked(address(this), address(this).codehash));
    }
}

contract CensorshipResistanceTestContract is
    VersionTestContract,
    AttestationTestContract,
    CensorshipResistanceGadget
{
    constructor(IAndromeda andromeda) AttestationTestContract(andromeda) {}

    function force(uint256 epoch) public force_cr(epoch) returns (uint256) {
        return cr_epoch;
    }

    function check(uint256 epoch) public check_cr(epoch) returns (uint256) {
        return cr_epoch;
    }

    function bump_epoch(uint256 epoch) public returns (uint256) {
        bump_cr_epoch(epoch);
        return cr_epoch;
    }
}

contract CensorshipResistanceGadget_Test is Test {
    AndromedaForge public andromeda;
    CensorshipResistanceTestContract testContract;

    function setUp() public {
        andromeda = new AndromedaForge();
        testContract = new CensorshipResistanceTestContract(andromeda);
    }

    function testCR() public {
        vm.expectRevert(bytes("cr: challenge not provided"));
        testContract.check(0); // restart challenge not solved
        vm.expectRevert(bytes("cr: challenge not provided"));
        testContract.force(0); // restart challenge not solved

        (bytes32 challenge, bytes memory attestation) = testContract.offchain_restart_challenge();
        (bytes32 challenge2,) = testContract.offchain_restart_challenge();
        require(challenge2 == challenge);
        testContract.onchain_restart_challenge(challenge, attestation);
        (bytes32 challenge3,) = testContract.offchain_restart_challenge();
        require(challenge3 == challenge);

        require(testContract.check(0) == 0);
        require(testContract.force(0) == 0);

        // Check explicit upgrade
        vm.expectRevert(bytes("cr: bump with invalid epoch"));
        testContract.bump_epoch(1);

        testContract.bump_epoch(0);

        vm.expectRevert(bytes("cr: caller epoch mismatch"));
        testContract.check(0);
        vm.expectRevert(bytes("cr: old epoch"));
        testContract.force(0);

        require(testContract.check(1) == 1);
        require(testContract.force(1) == 1);

        // Check implicit upgrade
        vm.expectRevert(bytes("cr: local view ahead of chain"));
        testContract.force(2);

        // Since we forced local epoch 2, both check and force with epoch 1 should fail
        vm.expectRevert(bytes("cr: local view ahead of chain"));
        testContract.check(1);
        vm.expectRevert(bytes("cr: local view ahead of chain"));
        testContract.force(1);

        // Make the chain match local epoch again
        testContract.bump_epoch(1);

        require(testContract.check(2) == 2);
        require(testContract.force(2) == 2);

        // TODO: simulate restart by clearing volatile memory (switchHost)
    }
}

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

bytes32 constant TEST_ROLE_1 = keccak256("TEST_ROLE_1");
bytes32 constant TEST_ROLE_2 = keccak256("TEST_ROLE_2");

contract AuthTestContract is AccessControl, CensorshipResistanceTestContract, AuthGadget {
    constructor(IAndromeda andromeda) CensorshipResistanceTestContract(andromeda) {}

    function _grant(bytes32 role, address account) public {
        _grantRole(role, account);
    }

    function _revoke(bytes32 role, address account) public {
        _revokeRole(role, account);
    }

    function hasRole(bytes32 role, address account)
        public
        view
        virtual
        override(AccessControl, AuthGadget)
        returns (bool)
    {
        return super.hasRole(role, account);
    }

    function require_auth() public auth(TEST_ROLE_1) returns (address) {
        return auth_signer;
    }

    function require_auth_query(bytes memory query, bytes memory signature)
        public
        auth_query(TEST_ROLE_1, query, signature)
        returns (address)
    {
        return auth_signer;
    }

    function require_reentrant() public auth(TEST_ROLE_1) {
        require_auth();
    }
}

contract AuthHelper {
    address public ext_address;
    uint256 public ext_privkey;

    constructor(IAndromeda andromeda) {
        ext_privkey = uint256(andromeda.localRandom());
        ext_address = Secp256k1.deriveAddress(ext_privkey);
    }

    function ext_sign(bytes memory data) public view returns (bytes memory signature) {
        signature = sign_raw(keccak256(data));
    }

    function sign_raw(bytes32 digest) public view returns (bytes memory signature) {
        signature = Secp256k1.sign(ext_privkey, digest);
    }
}

contract AuthGadget_Test is Test {
    AndromedaForge public andromeda;
    AuthTestContract private testContract;

    AuthHelper private authHelper;

    function setUp() public {
        andromeda = new AndromedaForge();
        testContract = new AuthTestContract(andromeda);
        authHelper = new AuthHelper(andromeda);
    }

    function testAuth() public {
        vm.expectRevert();
        testContract.require_auth();

        testContract._grant(TEST_ROLE_2, address(this));
        vm.expectRevert(bytes("auth: sender unauthorized"));
        testContract.require_auth();

        testContract._revoke(TEST_ROLE_2, address(this));
        testContract._grant(TEST_ROLE_1, address(this));
        require(testContract.require_auth() == address(this));

        testContract._revoke(TEST_ROLE_1, address(this));
        vm.expectRevert(bytes("auth: sender unauthorized"));
        testContract.require_auth();
    }

    function testReentrancy() public {
        testContract._grant(TEST_ROLE_1, address(this));
        vm.expectRevert();
        testContract.require_reentrant();
    }

    function testAuthQuery() public {
        bytes memory auth_query_data = abi.encodePacked(
            testContract.current_version(),
            testContract.current_epoch(),
            AuthTestContract.require_auth_query.selector,
            bytes("xoxo")
        );
        bytes memory signature = authHelper.ext_sign(auth_query_data);

        vm.expectRevert();
        testContract.require_auth_query("xoxo", signature);

        testContract._grant(TEST_ROLE_1, authHelper.ext_address());
        testContract.require_auth_query("xoxo", signature);
        require(testContract.require_auth_query("xoxo", signature) == authHelper.ext_address());

        vm.expectRevert();
        testContract.require_auth_query("xox2", signature);

        // wrong epoch
        testContract.bump_epoch(0);
        vm.expectRevert();
        testContract.require_auth_query("xoxo", signature);

        auth_query_data = abi.encodePacked(
            testContract.current_version(),
            testContract.current_epoch(),
            AuthTestContract.require_auth_query.selector,
            bytes("xoxo")
        );
        signature = authHelper.ext_sign(auth_query_data);
        require(testContract.require_auth_query("xoxo", signature) == authHelper.ext_address());

        // wrong version

        testContract.set_version_override("X");
        vm.expectRevert();
        testContract.require_auth_query("xoxo", signature);

        // recover
        testContract.clr_version_override();
        require(testContract.require_auth_query("xoxo", signature) == authHelper.ext_address());

        // wrong selector
        auth_query_data = abi.encodePacked(
            testContract.current_version(),
            testContract.current_epoch(),
            AuthTestContract.require_auth.selector,
            bytes("xoxo")
        );
        signature = authHelper.ext_sign(auth_query_data);
        vm.expectRevert();
        testContract.require_auth_query("xoxo", signature);

        // recovery
        auth_query_data = abi.encodePacked(
            testContract.current_version(),
            testContract.current_epoch(),
            AuthTestContract.require_auth_query.selector,
            bytes("xoxo")
        );
        signature = authHelper.ext_sign(auth_query_data);
        require(testContract.require_auth_query("xoxo", signature) == authHelper.ext_address());

        testContract._revoke(TEST_ROLE_1, authHelper.ext_address());
        vm.expectRevert();
        testContract.require_auth_query("xoxo", signature);
    }
}

contract KillswitchTestContract is AuthTestContract, KillswitchGadget {
    constructor(IAndromeda andromeda) AuthTestContract(andromeda) {}

    function hasRole(bytes32 role, address account)
        public
        view
        virtual
        override(AuthTestContract, AuthGadget)
        returns (bool)
    {
        return super.hasRole(role, account);
    }

    function _clr() public {
        Suave().volatileSet("local_killswitch", bytes32("0"));
    }

    /* ks should always be used with force_cr */
    function f(uint256 epoch) public ks force_cr(epoch) {}
}

contract KillswitchGadget_Test is Test {
    AndromedaForge public andromeda;
    AuthHelper private authHelper;

    function setUp() public {
        andromeda = new AndromedaForge();
        authHelper = new AuthHelper(andromeda);
    }

    function testKillswitch() public {
        KillswitchTestContract testContract = new KillswitchTestContract(andromeda);

        vm.expectRevert(bytes("cr: challenge not provided"));
        testContract.f(0); // restart challenge not solved

        (bytes32 challenge, bytes memory attestation) = testContract.offchain_restart_challenge();
        testContract.onchain_restart_challenge(challenge, attestation);

        // challenge provided, should now work
        testContract.f(0);

        testContract._grant(testContract.KILLSWITCH_ROLE(), address(this));

        testContract.onchain_killswitch("xoxo");
        vm.expectRevert(bytes("killswitch: onchain active"));
        testContract.f(0); // killswitch active

        require(testContract.killswitch_active() == true);
        assertEq(string(testContract.killswitch_reason()), string("xoxo"));

        // New contract for offchain ks
        // Separating into functions yields races!
        testContract = new KillswitchTestContract(andromeda);

        vm.expectRevert(bytes("cr: challenge not provided"));
        testContract.f(0); // restart challenge not solved

        (challenge, attestation) = testContract.offchain_restart_challenge();
        testContract.onchain_restart_challenge(challenge, attestation);

        // challenge provided, should now work
        testContract.f(0);

        testContract._grant(testContract.ATTESTED_KILLSWITCH_ROLE(), authHelper.ext_address());
        bytes memory signature =
            authHelper.sign_raw(testContract.auth_query_hash(KillswitchGadget.killswitch.selector, "xoxo"));
        attestation = testContract.killswitch(0, "xoxo", signature);

        vm.expectRevert(bytes("killswitch: local active"));
        testContract.f(0); // local killswitch active

        testContract._clr();
        testContract.f(0); // local killswitch not active any more

        // wrong reason
        vm.expectRevert(bytes("invalid attestation data"));
        testContract.onchain_attested_killswitch("xoxo2", attestation);

        testContract.onchain_attested_killswitch("xoxo", attestation);
        require(testContract.killswitch_active() == true);
        assertEq(string(testContract.killswitch_reason()), string("xoxo"));

        vm.expectRevert(bytes("killswitch: onchain active"));
        testContract.f(0); // local killswitch inactive, but onchain active
    }
}

contract TestKeyManager is KeyManager {
    IAndromeda suave;
    BIP32 bip32;
    bytes _local_seed;

    constructor(IAndromeda _suave) {
        suave = _suave;
        bip32 = new BIP32(suave);
        _local_seed = abi.encodePacked(suave.localRandom());
    }

    function _seed() private view returns (bytes memory) {
        return _local_seed;
    }

    function derive_pubkey(string memory path) public returns (bytes memory privkey) {
        (, BIP32.ExtendedPublicKey memory xpub) = bip32.deriveChildKeyPairFromPath(_seed(), path);
        return xpub.key;
    }

    function derive_privkey(string memory path) public returns (bytes32 privkey) {
        (BIP32.ExtendedPrivateKey memory xpriv,) = bip32.deriveChildKeyPairFromPath(_seed(), path);
        return xpriv.key;
    }

    function encrypt(string memory path, bytes memory plaintext) external returns (bytes memory ciphertext) {
        return PKE.encrypt(this.derive_pubkey(path), suave.localRandom(), plaintext);
    }

    function encrypt_to_pubkey(bytes memory pubkey, bytes memory plaintext)
        external
        view
        returns (bytes memory ciphertext)
    {
        return PKE.encrypt(pubkey, suave.localRandom(), plaintext);
    }

    function decrypt(string memory path, bytes memory ciphertext) external returns (bytes memory plaintext) {
        return PKE.decrypt(this.derive_privkey(path), ciphertext);
    }

    function refresh() external {}
}

contract EncryptedInputsTestContract is CensorshipResistanceTestContract, EncryptedInputsGadget {
    KeyManager _km;

    constructor(IAndromeda andromeda) CensorshipResistanceTestContract(andromeda) {
        _km = new TestKeyManager(andromeda);
    }

    function km() internal view virtual override returns (KeyManager) {
        return _km;
    }

    function f(uint256 epoch, encrypted_bytes memory data, bytes memory req_pubkey)
        external
        returns (encrypted_bytes memory enc_data)
    {
        bytes memory output = raw_f(decrypt_contract_inputs(data));
        enc_data = encrypt_output(req_pubkey, output);
    }

    function raw_f(bytes memory data) public returns (bytes memory) {
        return data;
    }
}

contract EncryptedInputsGadget_TestExt is Test {
    AndromedaForge public andromeda;

    function setUp() public {
        andromeda = new AndromedaForge();
    }

    // TODO: check rotation

    function testExtEncryption() public {
        EncryptedInputsTestContract testContract = new EncryptedInputsTestContract(andromeda);

        (bytes32 challenge, bytes memory attestation) = testContract.offchain_restart_challenge();
        testContract.onchain_restart_challenge(challenge, attestation);

        bytes memory pubkey;
        (pubkey, attestation) = testContract.rotate_contract_pubkey(testContract.current_epoch(), testContract.current_pubkey_nonce());
        testContract.onchain_rotate_pubkey(pubkey, attestation);

        // TODO: check bad epoch
        // TODO: check bad nonce
        bytes32 ext_privkey = andromeda.localRandom();
        bytes memory ext_pubkey = PKE.derivePubKey(ext_privkey);

        (uint256 epoch, uint256 nonce, encrypted_bytes memory ciphertext) =
            testContract.encrypt_contract_inputs(abi.encode("xoxo"), andromeda.localRandom());
        encrypted_bytes memory enc_output = testContract.f(epoch, ciphertext, ext_pubkey);
        assertEq(PKE.decrypt(ext_privkey, enc_output.data), abi.encode(bytes("xoxo")));
        assertEq(abi.decode(PKE.decrypt(ext_privkey, enc_output.data), (bytes)), bytes("xoxo"));
    }
}

contract EncryptedInputsGadget_TestCall is Test {
    AndromedaForge public andromeda;

    function setUp() public {
        andromeda = new AndromedaForge();
    }

    function testCallEncryption() public {
        EncryptedInputsTestContract testContract = new EncryptedInputsTestContract(andromeda);

        (bytes32 challenge, bytes memory attestation) = testContract.offchain_restart_challenge();
        testContract.onchain_restart_challenge(challenge, attestation);

        bytes memory pubkey;
        (pubkey, attestation) = testContract.rotate_contract_pubkey(testContract.current_epoch(), testContract.current_pubkey_nonce());
        testContract.onchain_rotate_pubkey(pubkey, attestation);

        // TODO: check bad epoch
        // TODO: check bad nonce
        bytes32 ext_privkey = andromeda.localRandom();
        bytes memory ext_enc_pubkey = PKE.derivePubKey(ext_privkey);
        (uint256 qx, uint256 qy) = Secp256k1.derivePubKey(uint256(ext_privkey));
        bytes memory ext_sign_pubkey = abi.encodePacked(qx, qy);

        (uint256 epoch, uint256 nonce, bytes memory encrypted_calldata) = testContract.encrypt_call(
            EncryptedInputsTestContract.raw_f.selector, abi.encode("xoxo"), andromeda.localRandom(), Secp256k1.deriveAddress(uint(ext_privkey))
        );

        bytes memory signature = Secp256k1.sign(
            uint256(ext_privkey), keccak256(abi.encodePacked(epoch, nonce, encrypted_calldata, ext_enc_pubkey))
        );

        require(
            Secp256k1.verify(
                Secp256k1.deriveAddress(ext_sign_pubkey),
                keccak256(abi.encodePacked(epoch, nonce, encrypted_calldata, ext_enc_pubkey)),
                signature
            )
        );

        encrypted_bytes memory enc_output = testContract.encrypted_dispatch(epoch, nonce, encrypted_calldata, ext_enc_pubkey, signature);
        assertEq(PKE.decrypt(ext_privkey, enc_output.data), abi.encode(bytes("xoxo")));
        assertEq(abi.decode(PKE.decrypt(ext_privkey, enc_output.data), (bytes)), bytes("xoxo"));
    }
}
