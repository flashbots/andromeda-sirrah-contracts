pragma solidity ^0.8.13;

import {PKE} from "src/crypto/encryption.sol";

import {VersionGadget} from "src/gadgets/VersionGadget.sol";
import {AttestationGadget} from "src/gadgets/AttestationGadget.sol";
import {CensorshipResistanceGadget} from "src/gadgets/CensorshipResistanceGadget.sol";
import {encrypted_bytes, EncryptedInputsGadget, KeyManager} from "src/gadgets/EncryptedInputsGadget.sol";
import {AuthGadget} from "src/gadgets/AuthGadget.sol";
import {KillswitchGadget} from "src/gadgets/KillswitchGadget.sol";

// kv secrets store
struct onchain_secret_data {
    bytes key; /* encrypted */
    bytes secret; /* encrypted */
    address owner; /* we store whoever produced the signature here */
}

/* Users should derive from SirrahSecretsManagerBase and implement the missing functions */
abstract contract SirrahSecretsManagerBase is
    VersionGadget,
    AttestationGadget,
    CensorshipResistanceGadget,
    AuthGadget,
    KillswitchGadget,
    EncryptedInputsGadget
{
    // Web3 (ecdsa secp256k1) key management
    mapping(bytes32 /* keccak256(version, nonce, path) */ => bytes /* encrypted key */) key_overrides; /* used for migrating */

    struct pubkey_data {
        uint256 nonce; /* used for rotation (rotates both pub and priv) */
        bytes pubkey;
        address owner;
    }

    mapping(string => pubkey_data) public published_pubkeys; /* todo: allow rotation */

    bytes32 public constant SECRETS_STORE_READ_ROLE = keccak256("secrets_store_read");
    bytes32 public constant SECRETS_STORE_WRITE_ROLE = keccak256("secrets_store_write");

    /* call with encrypted path */
    function derive_pubkey(uint256 epoch, encrypted_bytes memory path, uint256 nonce, bytes memory signature)
        external
        returns (bytes memory pubkey, bytes memory attestation)
    {
        return raw_derive_pubkey(epoch, string(decrypt_contract_inputs(path)), nonce, signature);
    }

    /* call through derive_pubkey or encrypted_dispatch */
    function raw_derive_pubkey(uint256 epoch, string memory path, uint256 nonce, bytes memory signature)
        internal
        ks
        check_cr(epoch)
        auth_query(SECRETS_STORE_WRITE_ROLE, abi.encode(path, nonce), signature)
        returns (bytes memory pubkey, bytes memory attestation)
    {
        // Check migrated keys
        bytes memory ov_privkey = key_overrides[keccak256(abi.encodePacked(current_version(), nonce, path))];
        if (ov_privkey.length != 0) {
            // migrated key, derive from stored priv
            // TODO: decrypt the key!
            pubkey = PKE.derivePubKey(bytes32(ov_privkey));
        } else {
            pubkey = keyManager().derive_pubkey(_web3_key_versioned_derive_path(path, nonce));
        }
        attestation = offchain_attest(
            this.onchain_store_pubkey.selector,
            abi.encode(
                _store_pubkey_att_data(
                    current_version(), path, nonce, pubkey, auth_signer /* populated by auth_query */
                )
            )
        );
    }

    // Typed attestation helper
    struct _store_pubkey_att_data {
        bytes32 version;
        string path;
        uint256 nonce;
        bytes pubkey;
        address owner;
    }

    // only this contract has access to keys store in this mapping
    function onchain_store_pubkey(
        string memory path,
        uint256 nonce,
        bytes memory pubkey,
        address owner,
        bytes memory attestation
    )
        public
        ks
        onchain_verify(abi.encode(_store_pubkey_att_data(current_version(), path, nonce, pubkey, owner)), attestation)
    {
        require(
            published_pubkeys[path].pubkey.length == 0
                || (
                    published_pubkeys[path].nonce == nonce && keccak256(published_pubkeys[path].pubkey) == keccak256(pubkey)
                        && published_pubkeys[path].owner == owner
                )
        );
        published_pubkeys[path] = pubkey_data(nonce, pubkey, owner);
    }

    // TODO: make sure this can't be used as a DoS vector on the rotated key
    function rotate_pubkey(uint256 epoch, encrypted_bytes memory path, uint256 nonce, bytes memory signature)
        external
        returns (bytes memory)
    {
        return raw_rotate_pubkey(epoch, string(decrypt_contract_inputs(path)), nonce, signature);
    }

    function raw_rotate_pubkey(uint256 epoch, string memory path, uint256 nonce, bytes memory signature)
        internal
        ks
        force_cr(epoch)
        auth_query(SECRETS_STORE_WRITE_ROLE, abi.encode(path, nonce), signature)
        returns (bytes memory)
    {
        // TODO!
        _web3_key_versioned_derive_path(path, nonce);
        return bytes("");
    }

    function derive_privkey(
        uint256 epoch,
        encrypted_bytes memory path,
        uint256 nonce,
        encrypted_bytes memory req_pubkey,
        bytes memory signature
    ) public returns (encrypted_bytes memory privkey, bytes memory attestation) {
        return raw_derive_privkey(
            epoch, string(decrypt_contract_inputs(path)), nonce, decrypt_contract_inputs(req_pubkey), signature
        );
    }

    function raw_derive_privkey(
        uint256 epoch,
        string memory path,
        uint256 nonce,
        bytes memory req_pubkey,
        bytes memory signature
    )
        public
        ks
        check_cr(epoch)
        auth_query(SECRETS_STORE_WRITE_ROLE, abi.encode(path, nonce, req_pubkey), signature)
        returns (encrypted_bytes memory privkey, bytes memory attestation)
    {
        string memory hd_path = _web3_key_versioned_derive_path(path, nonce);
        bytes32 raw_privkey = keyManager().derive_privkey(hd_path);

        privkey = encrypt_output(req_pubkey, abi.encodePacked(raw_privkey));
        bytes memory attestation_data = abi.encodePacked(path, nonce, raw_privkey);
        attestation = offchain_attest(this.derive_privkey.selector, attestation_data);
    }

    function _web3_key_versioned_derive_path(string memory path, uint256 nonce) private returns (string memory) {
        return versioned_derive_path(string.concat("m/9'/2'/", path, "/", string(abi.encodePacked(uint32(nonce))), "'"));
    }

    mapping(bytes32 => onchain_secret_data[]) onchain_secrets;

    /* call with encrypted key and secret */
    function store_secret(
        uint256 epoch,
        bytes32 version,
        encrypted_bytes memory key,
        encrypted_bytes memory secret,
        bytes memory signature
    ) external returns (bytes memory onchain_key, bytes memory onchain_secret, bytes memory attestation) {
        return
            raw_store_secret(epoch, version, decrypt_contract_inputs(key), decrypt_contract_inputs(secret), signature);
    }

    /* call through store_secret or encrypted_dispatch */
    function raw_store_secret(
        uint256 epoch,
        bytes32 version,
        bytes memory key,
        bytes memory secret,
        bytes memory signature
    )
        internal
        ks
        force_cr(epoch)
        auth_query(SECRETS_STORE_WRITE_ROLE, abi.encode(version, key, secret), signature)
        returns (bytes memory onchain_key, bytes memory onchain_secret, bytes memory attestation)
    {
        {
            require(current_version() == version);
            onchain_key = keyManager().encrypt(versioned_derive_path("m/17'/0'"), key);
            onchain_secret = keyManager().encrypt(versioned_derive_path("m/17'/1'"), secret);
        }

        {
            bytes32 control = keccak256(abi.encodePacked(version, key, secret));
            bytes memory attestation_data = abi.encode(
                _store_secret_attestation_data(
                    version, onchain_key, onchain_secret, auth_signer, /* from auth_query */ control
                )
            );
            attestation = offchain_attest(this.onchain_store_secret.selector, attestation_data);
        }
    }
    /* rotate secret? for now done through store+remove */

    // Typed attestation helper (can be autogenerated)
    struct _store_secret_attestation_data {
        bytes32 version;
        bytes encrypted_key;
        bytes encrypted_secret;
        address owner;
        bytes32 control; // keccak256(key||secret) for the initial caller to verify
    }

    function onchain_store_secret(
        bytes32 version,
        bytes memory key,
        bytes memory secret,
        address owner,
        bytes32 control,
        bytes memory attestation
    )
        public
        ks
        onchain_verify(abi.encode(_store_secret_attestation_data(version, key, secret, owner, control)), attestation)
    {
        require(current_version() == version);
        onchain_secrets[version].push(onchain_secret_data(key, secret, owner));
    }

    function retrieve_secret(
        uint256 epoch,
        encrypted_bytes memory key,
        encrypted_bytes memory req_pubkey,
        bytes memory signature
    ) external returns (encrypted_bytes memory secret, bytes memory attestation) {
        return raw_retrieve_secret(epoch, decrypt_contract_inputs(key), decrypt_contract_inputs(req_pubkey), signature);
    }

    function raw_retrieve_secret(uint256 epoch, bytes memory key, bytes memory req_pubkey, bytes memory signature)
        internal
        ks
        check_cr(epoch)
        auth_query(SECRETS_STORE_READ_ROLE, abi.encode(key, req_pubkey), signature)
        returns (encrypted_bytes memory encrypted_secret, bytes memory attestation)
    {
        for (uint256 i = 0; i < onchain_secrets[current_version()].length; i++) {
            if (
                keccak256(keyManager().decrypt("m/17'/0'", onchain_secrets[current_version()][i].key)) == keccak256(key)
            ) {
                bytes memory raw_secret = keyManager().decrypt(
                    versioned_derive_path("m/17'/1'"), onchain_secrets[current_version()][i].secret
                );
                encrypted_secret = encrypt_output(req_pubkey, raw_secret);
                attestation = offchain_attest(this.retrieve_secret.selector, abi.encodePacked(key, raw_secret));
            }
        }

        revert();
    }

    function remove_secret(uint256 epoch, bytes32 version, encrypted_bytes memory key, bytes memory signature)
        public
        returns (bytes memory onchain_key, bytes memory attestation)
    {
        return raw_remove_secret(epoch, version, decrypt_contract_inputs(key), signature);
    }

    function raw_remove_secret(uint256 epoch, bytes32 version, bytes memory key, bytes memory signature)
        public
        ks
        force_cr(epoch)
        auth_query(SECRETS_STORE_WRITE_ROLE, abi.encode(version, key), signature)
        returns (bytes memory onchain_key, bytes memory attestation)
    {
        require(version == current_version());

        for (uint256 i = 0; i < onchain_secrets[version].length; i++) {
            if (onchain_secrets[version][i].owner == auth_signer /* populated by auth_query */ ) {
                onchain_secret_data memory os = onchain_secrets[version][i];
                if (keccak256(keyManager().decrypt("m/17'/0'", os.key)) == keccak256(key)) {
                    onchain_key = os.key;
                    attestation = offchain_attest(
                        this.onchain_remove_secret.selector, abi.encodePacked(version, i, os.key, os.owner, os.secret)
                    );
                }
            }
        }
    }

    function onchain_remove_secret(
        uint256 epoch,
        bytes32 version,
        uint256 index,
        bytes memory key,
        bytes memory secret,
        address owner,
        bytes memory attestation
    ) public onchain_verify(abi.encodePacked(epoch, version, key, secret, owner), attestation) {
        require(version == current_version());
        require(keccak256(onchain_secrets[version][index].key) == keccak256(key));
        require(keccak256(onchain_secrets[version][index].secret) == keccak256(secret));
        require(onchain_secrets[version][index].owner == owner);
        delete onchain_secrets[version][index]; /* leave it empty - moving would invalidate other removals */
    }

    /* invoked by governance (internal) */
    /*
    bytes32 migration_from_version;
    address migrate_from;
    bytes32 migration_to_version;
    address migrate_to;

    function onchain_start_migration(bytes32 from_version, bytes32 to_version, address to) internal {
        migration_from_version = from_version;
        migrate_to = to;
        migration_to_version = to_version;
    }

    /* invoked by each owner */
    /* todo: add web3 key migration */
    /*
    function migrate_secrets_to(
        uint256 epoch,
        MigratableSecretsManager new_secrets_manager,
        bytes32 old_version,
        bytes32 new_version
    )
        public
        ks_active
        force_cr(epoch)
        returns (
            onchain_secret[] secrets,
            address owner,
            address old_secrets_manager,
            bytes32 old_version,
            bytes32 new_version,
            bytes attestation
        )
    {
        require(migration_from_version == current_version());
        require(migration_from_version == old_version);
        require(migrate_to == new_secrets_manager);
        require(migration_to_version == new_version);

        onchain_secrets[] secrets_to_migrate;
        for (uint256 i = 0; i < onchain_secrets[migration_version].length; i++) {
            if (onchain_secrets[migration_version][i].owner == msg.caller) {
                secrets_to_migrate.push(
                    onchain_secret(
                        keyManager.decrypt(versioned_derive_path("m/17'/0'"), onchain_secrets[migration_version][i].key),
                        keyManager.decrypt(versioned_derive_path("m/17'/1'"), onchain_secrets[migration_version][i].secret),
                        msg.caller
                    )
                );
            }
        }

        return (
            new_secrets_manager.migrate_secrets(
                secrets_to_migrate, msg.caller, migration_from_version, migration_to_version
            )
        );
    }
    /* invoked by migrate_secrets_to */

    /*
    function migrate_secrets(
        uint256 epoch,
        onchain_secret[] raw_secrets,
        address owner,
        address old_secrets_manager,
        bytes32 old_version,
        bytes32 new_version
    )
        external
        ks
        force_cr(epoch)
        returns (
            onchain_secret[] secrets,
            address owner,
            address old_secrets_manager,
            bytes32 old_version,
            bytes32 new_version,
            bytes attestation
        )
    {
        require(msg.caller == old_secrets_manager);
        require(migrate_from == old_secrets_manager);
        require(migration_from_version == old_version);
        require(current_version() == new_version);

        onchain_secrets[] new_secrets;
        for (uint256 i = 0; i < raw_secrets.length; i++) {
            new_secrets.push(
                onchain_secret(
                    keyManager.encrypt(versioned_derive_path("m/17'/0'"), raw_secrets[0].key),
                    keyManager.encrypt(versioned_derive_path("m/17'/1'"), raw_secrets[0].secret),
                    owner
                )
            );
        }

        return (
            new_secrets,
            offchain_attest(
                this.onchain_migrate_secrets.selector,
                abi.encodePacked(new_secrets, owner, old_secrets_manager, old_version)
                )
        );
    }
    */

    /* attested to by migrate_secrets through migrate_secrets_to */
    /*
    function onchain_migrate_secrets(
        onchain_secret[] secrets,
        address owner,
        address old_secrets_manager,
        bytes32 old_version,
        bytes32 new_version,
        bytes attestation
    ) public ks onchain_verify(abi.encodePacked(secrets, owner, old_version, new_version), attestation) {
        require(msg.caller == owner);
        require(migrate_from == old_secrets_manager);
        require(migration_from_version == old_version);
        require(current_version() == new_version);
        for (uint256 i = 0; i < secrets.length; i++) {
            onchain_secrets[new_version].push(secrets[i]);
        }
    }
     */
}

interface MigratableSecretsManager {
    function migrate_secrets(
        uint256 epoch,
        onchain_secret_data[] memory raw_secrets,
        address owner,
        address old_secrets_manager,
        bytes32 old_version,
        bytes32 new_version
    ) external returns (onchain_secret_data[] memory new_secrets, bytes memory attestation);
}
