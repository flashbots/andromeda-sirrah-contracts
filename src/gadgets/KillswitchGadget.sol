pragma solidity ^0.8.19;

import {AuthGadget} from "src/gadgets/AuthGadget.sol";
import {AttestationGadget} from "src/gadgets/AttestationGadget.sol";
import {CensorshipResistanceGadget} from "src/gadgets/CensorshipResistanceGadget.sol";

import {IAndromeda} from "src/IAndromeda.sol";

abstract contract KillswitchGadget is AuthGadget, AttestationGadget, CensorshipResistanceGadget {
    // Killswitch - disaster damage control
    // Like versioning, but requires a migration instead of an upgrade
    bool killswitch_active;
    bytes killswitch_reason;

    // Enclave killswitch
    bytes32 public constant ATTESTED_KILLSWITCH_ROLE = keccak256("attested_killswitch");
    // Governance killswitch
    bytes32 public constant KILLSWITCH_ROLE = keccak256("killswitch");

    // local kettle view before onchain trigger
    // killswitch should require reaching to other kettles after a restart
    //   to prevent restarting the kettle after the offchain trigger is propagated but before it hits the chain
    function _get_local_killswitch() private returns (bool) {
        return Suave().volatileGet("local_killswitch") == bytes32("1");
    }

    function _set_local_killswitch() private {
        Suave().volatileSet("local_killswitch", bytes32("1"));
    }

    modifier ks( /* should we put check_cr here by default? */ ) {
        require(!killswitch_active);
        require(!_get_local_killswitch()); /* TODO: review onboarding after restart */
        _;
    }

    modifier ks_active() {
        require(killswitch_active);
        /* does not require local ks */
        _;
    }

    // Attested offchain killswitch (enclaves)
    function killswitch(uint256 epoch, bytes memory reason, bytes memory signature)
        public
        force_cr(epoch)
        auth_query(ATTESTED_KILLSWITCH_ROLE, reason, signature)
        returns (bytes memory attestation)
    {
        _set_local_killswitch(); /* does not prevent the kettle operator from restarting before ks is put on chain! mischief can still be about */
        return offchain_attest(this.onchain_attested_killswitch.selector, reason);
    }

    // Attested onchain counterpart (enclaves)
    function onchain_attested_killswitch(bytes memory reason, bytes memory attestation)
        public
        onchain_verify((reason), attestation)
    {
        require(!killswitch_active);
        killswitch_active = true;
        killswitch_reason = reason;
    }

    // Non-attested onchain version (governance / admin)
    function onchain_killswitch(bytes memory reason) public auth(KILLSWITCH_ROLE) {
        require(!killswitch_active);
        killswitch_active = true;
        killswitch_reason = reason;
    }
}
