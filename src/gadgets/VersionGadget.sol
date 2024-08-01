pragma solidity ^0.8.19;

abstract contract VersionGadget {
    // Return a hash of all the upgradable code
    function current_version() public virtual returns (bytes32);
    /* Example implemetation:
    function current_version() public override returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), excodehash(this), address(auth), extcodehash(auth), address(km), extcodehash(km));
    }
    */

    // Adds current version to derive path - automatically prevents access across upgrades
    function versioned_derive_path(bytes memory path) internal returns (bytes memory) {
        return bytes.concat(path, bytes("/"), abi.encodePacked(current_version()), bytes("'"));
    }

    function all_versions() public returns (bytes32[] memory) { /* TODO */ }
    /* TODO: allow using past versions, maybe */
}
