pragma solidity ^0.8.13;

import "./crypto/secp256k1.sol";
import "./crypto/encryption.sol";
import "./02-KeyManagerEz.sol";

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

// Now we'll fix the auction using the TEE coprocessor
contract SealedAuction is LeakyAuction {
    KeyManagerSN keymgr;

    constructor(KeyManagerSN _keymgr) {
        keymgr = _keymgr;
    }

    /*
    To initialize `SealedAuction auc`, some Kettle must invoke:
       `keymgr.offchain_DeriveKey(auc) -> dPub,v,r,s`
       `keymgr.onchain_DeriveKey(auc,dPub,v,r,s)`
    */
    function isInitialized() public view returns (bool) {
        return keymgr.derivedPub(address(this)).length != 0;
    }

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
        return PKE.encrypt(keymgr.derivedPub(address(this)), r, abi.encodePacked(bid));
    }

    // Called by any kettle to compute the second price
    function offline_Finalize() public returns (uint256 secondPrice_, bytes memory att) {
        require(block.number > auctionEndTime);

        // Store our local key
        bytes32 dPriv = keymgr.derivedPriv();

        // Decrypt each bid and compute second price
        uint256 best = 0;
        for (uint256 i = 0; i < bidders.length; i++) {
            bytes memory ciphertext = encBids[bidders[i]];
            uint256 bid = abi.decode(PKE.decrypt(dPriv, ciphertext), (uint256));
            if (bid > best) {
                secondPrice_ = best;
                best = bid;
            } else if (bid > secondPrice_) {
                secondPrice_ = bid;
            }
        }

        // Use the key manager attest
        att = keymgr.attest(bytes32(secondPrice_));
    }

    // Post the second price on-chain
    event Finalized(uint256 secondPrice);

    function onchain_Finalize(uint256 secondPrice_, bytes memory sig) public {
        require(block.number > auctionEndTime);
        require(keymgr.verify(address(this), bytes32(secondPrice_), sig));
        secondPrice = secondPrice_;
        emit Finalized(secondPrice);
    }
}
