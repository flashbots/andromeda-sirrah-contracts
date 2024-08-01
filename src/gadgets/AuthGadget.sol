pragma solidity ^0.8.19;

import {Secp256k1} from "src/crypto/secp256k1.sol";

abstract contract AuthGadget {
    /* https://docs.openzeppelin.com/contracts/4.x/api/access#AccessControl */
    function hasRole(bytes32 role, address account) internal virtual returns (bool);
    // Grants role based on quote provided (in particular - user data and enclave measurement
    function grantRole(bytes32 role, bytes memory quote, bytes memory user_data, address account)
        internal
        virtual
        returns (bool);
    // function revokeRole(bytes32 role, address account) virtual internal returns (bool);
    // function renounceRole(bytes32 role, address account) virtual internal returns (bool);

    // auth version relying only on the transaction signature
    modifier auth(bytes32 role) {
        require(hasRole(role, msg.sender));
        _;
    }
    // query should contain current_version() and cr_epoch!

    modifier auth_query(bytes32 role, bytes memory query, bytes memory signature) {
        require(Secp256k1.verify(msg.sender, keccak256(abi.encodePacked(msg.sender, query)), signature));
        require(hasRole(role, msg.sender));
        _;
    }
    // Local node helper

    function auth_query_hash(bytes32 role, bytes memory query) public returns (bytes32) {
        require(hasRole(role, msg.sender));
        return keccak256(abi.encodePacked(msg.sender, query));
    }
}
