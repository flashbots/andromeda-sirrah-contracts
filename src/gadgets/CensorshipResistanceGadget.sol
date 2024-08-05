pragma solidity ^0.8.19;

import {AttestationGadget} from "src/gadgets/AttestationGadget.sol";

abstract contract CensorshipResistanceGadget is AttestationGadget {
    // require explicit onchain challenge on kettle restart
    mapping(bytes32 => bool) private cr_challenges;
    uint private max_offchain_calls_per_epoch; /* hard limit how many times an offchain call can be performed without epoch bump (0 - no limit) */
    constructor(uint _max_offchain_calls_per_epoch) {
        max_offchain_calls_per_epoch = _max_offchain_calls_per_epoch;
    }

    function offchain_restart_challenge() public returns (bytes32 challenge, bytes memory attestation) {
        challenge = _get_local_challenge(); /* do not override previous local challenge to prevent dos */
        require(!cr_challenges[challenge], "cr: challenge already provided"); /* already challenged */
        attestation = offchain_attest(this.onchain_restart_challenge.selector, abi.encodePacked(challenge));
    }

    function onchain_restart_challenge(bytes32 challenge, bytes memory attestation)
        public
        onchain_verify(abi.encodePacked(challenge), attestation)
    {
        cr_challenges[challenge] = true;
    }
    // epoch as seen in volatile memory of the kettle (can be delayed if kettle operator censors calls)

    function _get_local_challenge() private returns (bytes32 challenge) {
        challenge = Suave().volatileGet("local_challenge");
        if (challenge == bytes32(0)) {
            challenge = Suave().localRandom();
            _set_uses_since_local_epoch_update(0);
            _set_local_challenge(challenge);
        }
    }

    function _set_local_challenge(bytes32 challenge) private {
        Suave().volatileSet("local_challenge", challenge);
    }

    // epoch as seen onchain (can be delayed if chain is censored)
    uint256 public cr_epoch;

    function current_epoch() public view returns (uint256) {
        return cr_epoch;
    }

    // epoch as seen in volatile memory of the kettle (can be delayed if kettle operator censors calls)
    function _get_local_epoch() private returns (uint256 epoch) {
        epoch = uint256(Suave().volatileGet("local_epoch"));
    }

    function _set_local_epoch(uint256 epoch) private {
        _set_uses_since_local_epoch_update(0);
        Suave().volatileSet(("local_epoch"), bytes32(epoch));
    }

    // Hard limit amount of requests the contract will allow be processed before it forces a re-challenge
    // The contract is expected to be bumped every now and then, and if we stop seeing cr epoch bumps
    //   we should assume the kettle operator is maliciously filtering out requests and force chain sync by clearing challenge
    function _set_uses_since_local_epoch_update(uint uses) private {
        Suave().volatileSet(("uses_since_epoch_update"), bytes32(uses));
    }
    function _get_uses_since_local_epoch_update()private returns (uint uses) {
        uses = uint256(Suave().volatileGet("uses_since_epoch_update"));
    }

    function verify_uses_since_last_epoch_update() private {
        if (max_offchain_calls_per_epoch == 0) {
            return;
        }
        uint uses_since_last_update = _get_uses_since_local_epoch_update();
        if (uses_since_last_update >= max_offchain_calls_per_epoch) {
            // force onchain challenge
            _set_local_challenge(Suave().localRandom());
            _set_uses_since_local_epoch_update(0);
            require(false, "cr: epoch update not seen for too long");
        } else {
            _set_uses_since_local_epoch_update(uses_since_last_update+1);
        }
    }

    // Onchain!
    function bump_cr_epoch(uint256 epoch) internal {
        require(cr_epoch == epoch, "cr: bump with invalid epoch");
        cr_epoch = epoch + 1;
    }

    // add the following modifiers to your calls to make them censorship resistant
    // upgrading the epoch via cr_check call will make the kettle *refuse* to serve previous epochs through this cr gadget
    //   until the chain state matches, *to all callers* to prevent selective censorship
    // VERY IMPORTANT! The caller must verify who sets the epoch as it can otherwise be a DoS vector!
    // use for things like forcing key rotations
    modifier force_cr(uint256 epoch) {
        /* IMPORTANT! This is set regardless of revert status */
        verify_uses_since_last_epoch_update();
        require(cr_challenges[_get_local_challenge()], "cr: challenge not provided");
        require(epoch >= cr_epoch, "cr: old epoch"); // resubmission, ignore - user's view is outdated
        uint256 c_local_epoch = _get_local_epoch();
        if (epoch > c_local_epoch) {
            // user requested epoch higher than kettle's local view - this means noone else did so before (can be benign)
            _set_local_epoch(epoch); // refuse to serve anything less than epoch in subsequent calls
            c_local_epoch = epoch; // use max(local, epoch) in the rest of the function
        }
        require(cr_epoch >= c_local_epoch, "cr: local view ahead of chain"); // local view of the chain must be at least until local epoch - otherwise the chain is being censored
        require(cr_epoch == epoch, "cr: caller epoch mismatch"); // and request and chain epochs must match - otherwise we are getting spoofed
        _;
    }

    // more benign version - does not enforce cr for other callers
    // the caller here only makes sure the local chain view is at least up to epoch
    modifier check_cr(uint256 epoch) {
        verify_uses_since_last_epoch_update();
        require(cr_challenges[_get_local_challenge()], "cr: challenge not provided");
        require(cr_epoch == epoch, "cr: caller epoch mismatch"); // request and chain epochs must match

        uint256 c_local_epoch = _get_local_epoch();
        require(cr_epoch >= c_local_epoch, "cr: local view ahead of chain"); // local view of the chain must be at least until local epoch. this means no user requested this kettle with a higher epoch

        if (cr_epoch > c_local_epoch) {
            // Always safe - bump local view to (local) chain view. Refuse to serve rollbacks
            _set_local_epoch(cr_epoch);
        }
        _;
    }
}
