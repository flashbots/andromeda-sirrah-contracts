pragma solidity ^0.8.13;

import "../crypto/secp256k1.sol";
import "../crypto/encryption.sol";

import {AndromedaForge} from "src/AndromedaForge.sol";
import {Secp256k1} from "src/crypto/secp256k1.sol";
import {PKE, Curve} from "src/crypto/encryption.sol";

// We'l start with a Leaky second price auction
contract LeakyAuction {
    // All Deposits in before trade
    mapping(address => uint256) public balance;

    // Concluding time (block height)
    uint256 public constant auctionEndTime = 2;

    // To be set after the auction concludes (this is the output)
    uint256 public secondPrice;

    // Store the Bids (in plaintext for now)
    mapping(address => uint256) public bids;
    address[] public bidders;

    // Accept a bid in plaintext
    event BidPlaced(address sender, uint256 bid);

    function submitBid(uint256 bid) public virtual {
        require(block.number <= auctionEndTime);
        require(bids[msg.sender] == 0);
        bids[msg.sender] = bid;
        bidders.push(msg.sender);
        emit BidPlaced(msg.sender, bid);
    }

    // Wrap up the auction and compute the 2nd price
    event Concluded(uint256 secondPrice);

    function conclude() public {
        require(block.number > auctionEndTime);
        require(secondPrice == 0);
        // Compute the second price
        uint256 best = 0;
        for (uint256 i = 0; i < bidders.length; i++) {
            uint256 bid = bids[bidders[i]];
            if (bid > best) {
                secondPrice = best;
                best = bid;
            } else if (bid > secondPrice) {
                secondPrice = bid;
            }
        }
        emit Concluded(secondPrice);
    }
}

contract KeyManager {
    AndromedaForge public Suave;

    constructor(AndromedaForge _Suave) {
        Suave = _Suave;
    }

    // Public key (once initialized) will be visible
    bytes xPub;

    // Private key will only be accessible in confidential mode
    function xPriv() internal returns (bytes32) {
        return Suave.volatileGet("xPriv");
    }

    // To initialize the key, some kettle must call this...
    function offchain_Bootstrap() public returns (bytes memory _xPub, bytes memory att) {
        bytes32 xPriv_ = Suave.localRandom();
        _xPub = PKE.derivePubKey(xPriv_);
        Suave.volatileSet("xPriv", xPriv_);
        att = Suave.attestSgx(keccak256(abi.encodePacked("xPub", _xPub)));
    }

    // ... and then post it on chain, verifying the attestation
    function onchain_Bootstrap(bytes memory _xPub, bytes memory att) public {
        require(xPub.length == 0); // only once
        Suave.verifySgx(address(this), keccak256(abi.encodePacked("xPub", _xPub)), att);
        xPub = _xPub;
    }
}

// Now we'll fix the auction using the TEE coprocessor
contract SealedAuction is LeakyAuction, KeyManager {
    constructor(AndromedaForge _Suave) KeyManager(_Suave) {}

    // Now we will store encrypted orders
    mapping(address => bytes) encBids;

    event EncryptedBidPlaced(address sender);

    function submitEncrypted(bytes memory ciphertext) public {
        require(block.number <= auctionEndTime);
        require(encBids[msg.sender].length == 0);
        encBids[msg.sender] = ciphertext;
        bidders.push(msg.sender);
        emit EncryptedBidPlaced(msg.sender);
    }

    // Helper function for a client to run locally
    function encryptOrder(uint256 bid, bytes32 r) public view returns (bytes memory) {
        return PKE.encrypt(xPub, r, abi.encodePacked(bid));
    }

    // Called by any kettle to compute the second price
    function offline_Finalize() public returns (uint256 secondPrice_, bytes memory att) {
        require(block.number > auctionEndTime);
        bytes32 xPriv = xPriv();

        // Decrypt each bid and compute second price
        uint256 best = 0;
        for (uint256 i = 0; i < bidders.length; i++) {
            bytes memory ciphertext = encBids[bidders[i]];
            uint256 bid = abi.decode(PKE.decrypt(xPriv, ciphertext), (uint256));
            if (bid > best) {
                secondPrice_ = best;
                best = bid;
            } else if (bid > secondPrice_) {
                secondPrice_ = bid;
            }
        }

        // Use the key manager attest
        att = Suave.attestSgx(keccak256(abi.encodePacked("2ndprice", secondPrice_)));
    }

    // Post the second price on-chain
    function onchain_Finalize(uint256 secondPrice_, bytes memory att) public {
        require(block.number > auctionEndTime);
        Suave.verifySgx(address(this), keccak256(abi.encodePacked("2ndprice", secondPrice_)), att);
        secondPrice = secondPrice_;
        emit Concluded(secondPrice);
    }
}
