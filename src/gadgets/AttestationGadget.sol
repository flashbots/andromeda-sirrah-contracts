pragma solidity ^0.8.19;

import {IAndromeda} from "src/IAndromeda.sol";

abstract contract AttestationGadget {
    function andromeda() internal view virtual returns (IAndromeda);

    modifier onchain_verify(bytes memory user_data, bytes memory attestation) virtual {
        onchain_verify_fn(msg.sig, user_data, attestation);
        _;
    }

    function onchain_verify_fn(bytes4 target, bytes memory user_data, bytes memory attestation) internal virtual {
        require(
            andromeda().verifySgx(
                address(this), keccak256(abi.encodePacked(target, address(this), user_data)), attestation
            ),
            "invalid attestation data"
        );
    }

    function offchain_attest(bytes4 target, bytes memory user_data)
        internal
        virtual
        returns (bytes memory attestation)
    {
        return andromeda().attestSgx(keccak256(abi.encodePacked(target, address(this), user_data)));
    }
}

/* TODO: provide signature-based attestation similar to KeyManagerBase as an alternative to the above */
