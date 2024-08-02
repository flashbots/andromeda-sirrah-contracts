pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Strings.sol";

abstract contract VersionGadget {
    // Return a hash of all the upgradable code
    function current_version() public virtual returns (bytes32);
    /* Example implemetation:
    function current_version() public override returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), excodehash(this), address(auth), extcodehash(auth), address(km), extcodehash(km));
    }
    */

    // Adds current version to derive path - automatically prevents access across upgrades
    function versioned_derive_path(string memory path) internal returns (string memory) {
        // TODO: verify we don't truncate the version too much. if it's always a hash this should be fine.
        return string.concat(path, "/", uint32_to_path(uint32(uint256(current_version()))));
    }

    function uint32_to_path(uint32 n) public returns (string memory) {
        return string.concat(Strings.toString(n / 2), "'");
    }

    // function all_versions() public returns (bytes32[] memory) { /* TODO */ }
    /* TODO: allow using past versions, maybe */
    function previous_versioned_derive_path(bytes32 version, bytes memory path) internal returns (bytes memory) {
        require(version != current_version());
        // require(version in all_versions());
        return bytes.concat(path, bytes("/"), abi.encodePacked(version), bytes("'"));
    }
}
