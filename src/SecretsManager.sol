pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IAndromeda} from "src/IAndromeda.sol";

import {BIP32} from "src/BIP32.sol";
import {KeyManager_v0} from "src/KeyManager.sol";

import "src/SecretsManagerBase.sol";

/* Users should derive from SirrahSecretsManagerBase and implement the missing functions */
contract SirrahSecretsManager_V0 is SirrahSecretsManagerBase {
    IAndromeda private m_andromeda;
    DummySecretsManagerAccessControl private m_ac;
    KeyManager private m_km;

    constructor(IAndromeda _andromeda, KeyManager _km) CensorshipResistanceGadget(100) {
        m_andromeda = _andromeda;
        m_ac = new DummySecretsManagerAccessControl(m_andromeda);
        m_km = _km;
    }

    function current_version() public virtual override returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                address(this),
                address(this).codehash,
                address(m_andromeda),
                address(m_andromeda).codehash,
                address(m_ac),
                address(m_ac).codehash
            )
        );
    }

    function andromeda() internal view virtual override returns (IAndromeda) {
        return m_andromeda;
    }

    function keyManager() internal view virtual override returns (KeyManager) {
        return m_km;
    }

    function hasRole(bytes32 role, address account) public view virtual override returns (bool) {
        return m_ac.hasRole(role, account);
    }
}

/* Grants access based on private key signature rather than attestation */
contract DummySecretsManagerAccessControl is AttestationGadget, AccessControl {
    IAndromeda private m_andromeda;

    constructor(IAndromeda _andromeda) {
        m_andromeda = _andromeda;
    }

    function andromeda() internal view virtual override returns (IAndromeda) {
        return m_andromeda;
    }
}

contract BIP32KeyManager is KeyManager {
    IAndromeda suave;
    BIP32 bip32;
    KeyManager_v0 m_km; // must be bootstrapped elsewhere

    constructor(IAndromeda _suave, KeyManager_v0 _km) {
        suave = _suave;
        bip32 = new BIP32(suave);
        m_km = _km;
    }

    function _seed() private returns (bytes memory) {
        return abi.encodePacked(m_km.derivedPriv());
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
}
