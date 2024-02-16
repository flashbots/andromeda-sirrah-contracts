pragma solidity ^0.8.13;

import "../../lib/revm-services/Interfaces.sol";
import "../crypto/secp256k1.sol";
import "../crypto/encryption.sol";

import "../KeyHelper.sol";

struct Bundle {
    uint256 height;
    bytes transaction;
    uint256 profit;
}

// TODO: should probably be gated behind onlyOwner
contract RedisStore is KeyHelper, WithRedis, WithRedisPubsub {
    bytes32 r;
    constructor(KeyManager_v0 keymgr, bytes32 _r) KeyHelper(keymgr) WithRedis() WithRedisPubsub() {
        r = _r;
    }

    function set(string memory key, bytes memory data) public {
        redis().set(_format_key(key), auth_encrypt(data));
    }

    function get(string memory key) public returns (bool, bytes memory) {
        bytes memory data = redis().get(_format_key(key));
        if (data.length == 0) {
            return (false, "");
        }
        return auth_decrypt(data);
    }

    function publish(string memory topic, bytes memory message) public {
        pubsub().publish(_format_topic(topic), auth_encrypt(message));
    }

    function subscribe(string memory topic) public {
       pubsub().subscribe(_format_topic(topic));
    }

    function unsubscribe(string memory topic) public {
        pubsub().unsubscribe(_format_topic(topic));
    }

    function get_message(string memory topic) public returns (bool /* msg present */, bool /* auth ok */, bytes memory /* message */) {
        // Requires subscribe is called first (per kettle!)
        bytes memory message = pubsub().get_message(_format_topic(topic));
        if (message.length == 0) {
            return (false, false, "");
        }
        (bool auth_ok, bytes memory decrypted_msg) = auth_decrypt(message);
        return (true, auth_ok, decrypted_msg);
    }

    function _format_key(string memory key) private view returns (string memory) {
        return string(abi.encodePacked(keccak256(abi.encodePacked(r, key))));
    }
    function _format_topic(string memory topic) private view returns (string memory) {
        return string(abi.encodePacked(keccak256(abi.encodePacked(r, topic))));
    }
}

contract BundleConfidentialStore is KeyHelper {
    RedisStore private redis;
    constructor(KeyManager_v0 _keymgr, address[] memory _allowedContracts) KeyHelper(_keymgr) {
        redis = new RedisStore(_keymgr, keccak256(abi.encodePacked(tx.origin, msg.sender, block.number)));
        for (uint i = 0; i < _allowedContracts.length; i++) {
            allowedContracts[_allowedContracts[i]] = true;
        }
    }

    /* Encrypt yourself using the pubkey, or use your own local suave chain node! */
    function encryptBundle(Bundle memory bundle, bytes32 r) public view returns (bytes memory) {
        return encrypt(abi.encode(bundle), r);
    }

    /* Debug functions exposing internals. Those are here just for the demo! */
    function publishEncryptedBundle(bytes memory encryptedBundle) external {
        Bundle memory bundle = abi.decode(decrypt(encryptedBundle), (Bundle));
        redis.publish("bundles", abi.encode(bundle));
    }
    function pollAndReturnBundle() external returns (bool msg_present, bool auth_ok, Bundle memory bundle) {
        (bool _msg_present, bool _auth_ok, bytes memory raw_message) = redis.get_message("bundles");
        msg_present = _msg_present;
        auth_ok = _auth_ok;
        if (_msg_present && _auth_ok && raw_message.length != 0) {
            bundle = abi.decode(raw_message, (Bundle));
            internal_addBundle(bundle);
        }

        return (msg_present, auth_ok, bundle);
    }
    function dbg_getBundlesByHeight(uint256 height) external returns (Bundle[] memory bundles) {
        allowedContracts[msg.sender] = true;
        return getBundlesByHeight(height);
    }
    /* End of debug functions */


    function addBundle(Bundle memory bundle) public onlyAllowed {
        internal_addBundle(bundle);

        // Note: bundle already includes profit, does not have to be re-calculated
        redis.publish("bundles", abi.encode(bundle));
    }

    function internal_addBundle(Bundle memory bundle) internal {
        // TODO: check if bundle is already present!

        bytes32 bundleHash = keccak256(abi.encode(bundle));
        redis.set(string(abi.encodePacked("bundle-", bundleHash)), abi.encode(bundle));

        // Updates bundle by height index
        // TODO: this would be much faster with a key index / hset
        bytes32[] memory n_bundles;
        (bool found, bytes memory c_bundles_raw) = redis.get(string(abi.encodePacked("bundles-", bundle.height)));
        if (found && c_bundles_raw.length > 0) {
            bytes32[] memory c_bundles = abi.decode(c_bundles_raw, (bytes32[]));
            n_bundles = new bytes32[](c_bundles.length+1);
            n_bundles[c_bundles.length] = bundleHash;
            for (uint i = 0; i < c_bundles.length; i++) {
                n_bundles[i] = c_bundles[i];
            }
        } else {
            n_bundles = new bytes32[](1);
            n_bundles[0] = bundleHash;
        }

        redis.set(string(abi.encodePacked("bundles-", bundle.height)), abi.encode(n_bundles));
    }

    function getBundlesByHeight(uint256 height) public onlyAllowed returns (Bundle[] memory bundles) {
        (bool index_found, bytes memory c_bundles_raw) = redis.get(string(abi.encodePacked("bundles-", height)));
        if (!index_found || c_bundles_raw.length == 0) {
            return bundles;
        }

        bytes32[] memory c_bundles = abi.decode(c_bundles_raw, (bytes32[]));
        bundles = new Bundle[](c_bundles.length);
        for (uint i = 0; i < c_bundles.length; i++) {
            (bool bundle_found, bytes memory bundle_raw) = redis.get(string(abi.encodePacked("bundle-", c_bundles[i])));
            if (!bundle_found || bundle_raw.length > 0) {
                bundles[i] = abi.decode(bundle_raw, (Bundle));
            } else {
                // wat do?
            }
        }
    }

    // Call on each kettle to queue synchronization messages
    function subscribe() external {
        redis.subscribe("bundles");
    }

    // Call on each kettle to process synchronization messages
    // Returns how many messages were processed
    function synchronize(uint maxMsgs) external returns (uint) {
        for (uint i = 0; i < maxMsgs; i++) {
            (bool msg_present, bool msg_auth_ok, bytes memory raw_message) = redis.get_message("bundles");
            if (!msg_present) {
                return i;
            } else if (!msg_auth_ok || raw_message.length == 0) {
                continue;
            }

            Bundle memory bundle = abi.decode(raw_message, (Bundle));
            internal_addBundle(bundle);
        }

        return maxMsgs;
    }


    mapping (address => bool) allowedContracts;
    modifier onlyAllowed() {
        require(msg.sender == address(this) || allowedContracts[msg.sender], "caller not allowed");
        _;
    }


    /* If you want to pass in encrypted data, first encrypt it (yourself using the pubkey or encrypt() with your local node), it and then call */
    /* Usually however, you'll want to handle encryption in the parent contract (see DBBSample) */
    function _decrypt_and_call(bytes memory ciphertext, bytes memory cdata) onlyAllowed external returns (bytes memory) {
        bytes memory plaintext = decrypt(ciphertext);
        (bool call_ok, bytes memory return_data) = address(this).call(bytes.concat(cdata, plaintext));
        require(call_ok);
        return return_data;
    }
}

/* Usage example */
contract DBBSample is KeyHelper {
    BundleConfidentialStore store;
    Builder builder;
    constructor(KeyManager_v0 keymgr) KeyHelper(keymgr) {
        address[] memory allowedContracts = new address[](1);
        allowedContracts[0] = address(this);
        store = new BundleConfidentialStore(keymgr, allowedContracts); 
        builder = new Builder();
    }

    // Call for every kettle to start accepting bundles from them!
    function offchain_onboardKettle() public {
        store.subscribe();
    }

    /* Encrypt yourself using the pubkey, or use your own local suave chain node! */
    function encryptBundle(Bundle memory bundle) public view returns (bytes memory) {
        return encrypt(abi.encode(bundle));
    }
    function decryptBundle(bytes memory ciphertext) internal returns (Bundle memory) {
        return abi.decode(decrypt(ciphertext), (Bundle));
    }

    function submitEncryptedBundle(bytes memory encryptedBundle) external {
        Bundle memory bundle = decryptBundle(encryptedBundle);
        // Note that bundle is not trusted despite being encrypted!

        Bundle memory simulatedBundle = builder.simulate(bundle);
        store.addBundle(simulatedBundle);
    }

    /* Call before buildBlock to fetch bundles from other kettles */
    /* Returns whether there are more messages to be synchronized */
    /* If reverts with out of gas, there are still possibly messages pending! */
    function synchronize_store() external returns (bool) {
        /* TODO: run until no more gas */
        return store.synchronize(10) != 10;
    }

    function buildBlock(uint256 height) external {
        /* Make sure you are calling synchronize_store in the background! */
        Bundle[] memory bundles = store.getBundlesByHeight(height);
        uint256 _blockProfit = builder.buildBlock(bundles);
        /* Do something with the block */
    }
}

contract Builder {
    function simulate(Bundle memory bundle) public pure returns (Bundle memory) {
        bundle.profit = 1;
        return bundle;
    }

    function buildBlock(Bundle[] memory bundles) public pure returns (uint256) {
        uint256 profit = 0;
        for (uint i = 0; i < bundles.length; i++) {
            profit += bundles[i].profit;
        }
        return profit;
    }
}


