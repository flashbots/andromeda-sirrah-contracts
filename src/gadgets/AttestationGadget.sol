pragma solidity ^0.8.19;

abstract contract AttestationGadget {
    function offchain_attest(bytes32 user_data) internal virtual returns (bytes memory attestation); // Generate MEVM-side attestation of user data for computation integrity guarantee
    function onchain_verify_attestation(bytes32 user_data, bytes memory attestation) internal virtual returns (bool); // Verify the attestation produced by offchain_attest, can be done onchain

    modifier onchain_verify(bytes memory user_data, bytes memory attestation) virtual {
        onchain_verify_fn(msg.sig, user_data, attestation);
        _;
    }

    function onchain_verify_fn(bytes4 target, bytes memory user_data, bytes memory attestation) public virtual {
        require(onchain_verify_attestation(keccak256(abi.encodePacked(target, address(this), user_data)), attestation));
    }

    function offchain_attest(bytes4 target, bytes memory user_data)
        internal
        virtual
        returns (bytes memory attestation)
    {
        return offchain_attest(keccak256(abi.encodePacked(target, address(this), user_data)));
    }
}
