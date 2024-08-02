pragma solidity ^0.8.19;

import {IAndromeda} from "src/IAndromeda.sol";

abstract contract AttestationGadget {
    function Suave() internal view virtual returns (IAndromeda);

    modifier onchain_verify(bytes memory user_data, bytes memory attestation) virtual {
        onchain_verify_fn(msg.sig, user_data, attestation);
        _;
    }

    function onchain_verify_fn(bytes4 target, bytes memory user_data, bytes memory attestation) internal virtual {
        require(
            Suave().verifySgx(address(this), keccak256(abi.encodePacked(target, address(this), user_data)), attestation),
            "invalid attestation data"
        );
    }

    function offchain_attest(bytes4 target, bytes memory user_data)
        internal
        virtual
        returns (bytes memory attestation)
    {
        return Suave().attestSgx(keccak256(abi.encodePacked(target, address(this), user_data)));
    }
}
