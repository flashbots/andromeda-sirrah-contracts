pragma solidity ^0.8.19;

import {Secp256k1} from "src/crypto/secp256k1.sol";

import {VersionGadget} from "src/gadgets/VersionGadget.sol";
import {CensorshipResistanceGadget} from "src/gadgets/CensorshipResistanceGadget.sol";

abstract contract AuthGadget is VersionGadget, CensorshipResistanceGadget {
    /* https://docs.openzeppelin.com/contracts/4.x/api/access#AccessControl */
    function hasRole(bytes32 role, address account) public view virtual returns (bool);

    // function grantRole(bytes32 role, bytes memory quote, bytes memory user_data, address account) internal virtual returns (bool);
    // function revokeRole(bytes32 role, address account) virtual internal returns (bool);
    // function renounceRole(bytes32 role, address account) virtual internal returns (bool);

    // Reentrancy check and signer lookup
    address internal auth_signer;

    // auth version relying only on the transaction signature
    modifier auth(bytes32 role) {
        // Nonreentrant
        require(auth_signer == address(0), "auth: reentrancy");
        require(hasRole(role, msg.sender), "auth: sender unauthorized");

        auth_signer = msg.sender;
        _;
        auth_signer = address(0);
    }

    modifier auth_query(bytes32 role, bytes memory query, bytes memory signature) {
        require(auth_signer == address(0), "auth: reentrancy");
        bytes32 digest = keccak256(abi.encodePacked(current_version(), current_epoch(), msg.sig, query));
        address signer = Secp256k1.recover_signer(digest, signature);
        require(Secp256k1.verify(signer, digest, signature), "auth: invalid signature");
        require(hasRole(role, signer), "auth: signer unauthorized");

        auth_signer = signer;
        _;
        auth_signer = address(0);
    }

    // Local node helper
    function auth_query_hash(bytes4 method, bytes memory query) public returns (bytes32) {
        return keccak256(abi.encodePacked(current_version(), current_epoch(), method, query));
    }
}
