pragma solidity ^0.8.13;

import "../../lib/revm-services/Interfaces.sol";
import "../crypto/secp256k1.sol";
import "../crypto/encryption.sol";
import "../KeyManager.sol";

contract KeyHelper {
    KeyManager_v0 keymgr;

    constructor(KeyManager_v0 _keymgr) {
        keymgr = _keymgr;
    }

    /*
    To initialize, some Kettle must invoke:
       `keymgr.offchain_DeriveKey(auc) -> dPub,v,r,s`
       `keymgr.onchain_DeriveKey(auc,dPub,v,r,s)`
    */
    function isInitialized() public view returns (bool) {
        return storePubkey().length != 0;
    }
    function storePubkey() internal view returns (bytes memory) {
        return keymgr.derivedPub(address(this));
    }
    function storePrivkey() internal returns (bytes32) {
        return keymgr.derivedPriv();
    }

    function encrypt(bytes memory message, bytes32 r) internal view returns (bytes memory) {
        return PKE.encrypt(storePubkey(), r, message);
    }
    function encrypt(string memory message, bytes32 r) internal view returns (string memory) {
        return string(encrypt(abi.encodePacked(message), r));
    }
    function encrypt(bytes memory message) internal view returns (bytes memory) {
        return encrypt(message, keymgr.Suave().localRandom());
    }
    function encrypt(string memory message) internal view returns (string memory) {
        return string(encrypt(abi.encodePacked(message), keymgr.Suave().localRandom()));
    }

    function decrypt(bytes memory ciphertext) internal returns (bytes memory message) {
        return PKE.decrypt(storePrivkey(), ciphertext);
    }
}

contract RedisStore is KeyHelper, WithRedis, RedisSubscriber {
    bytes32 r;
    constructor(KeyManager_v0 keymgr, bytes32 _r) KeyHelper(keymgr) {
        r = _r;
    }

    function set(string memory key, bytes memory data) internal {
        redis().set(encrypt(key, r), encrypt(data));
    }

    function get(string memory key) internal returns (bytes memory) {
        return decrypt(redis().get(encrypt(key, r)));
    }

    function publish(string memory topic, bytes memory message) internal {
        redis().publish(encrypt(topic, r), encrypt(message));
    }

    function subscribe(string memory topic) internal {
        redis().subscribe(encrypt(topic, r), address(this));
    }

    function unsubscribe(string memory topic) internal {
        redis().unsubscribe(encrypt(topic, r), address(this));
    }

    function get_message(string memory topic) internal returns (bytes memory) {
        // Requires subscribe is called first (per kettle!)
        bytes memory message = redis().get_message(encrypt(topic, r), address(this));
        if (message.length == 0) {
            return message;
        }
        return decrypt(message);
    }

    function onRedisMessage(string memory topic, bytes memory message) public virtual {
        // Callbacks not implemented yet!
    }
}

struct Bundle {
    uint256 height;
    bytes transaction;
    uint256 profit;
}

contract BundleConfidentialStore is RedisStore {
    constructor(KeyManager_v0 keymgr, address[] memory _allowedContracts) RedisStore(keymgr, keccak256(abi.encodePacked(tx.origin, msg.sender, block.number))) {
        for (uint i = 0; i < _allowedContracts.length; i++) {
            allowedContracts[_allowedContracts[i]] = true;
        }
    }

    mapping (address => bool) allowedContracts;
    modifier onlyAllowed() {
        require(allowedContracts[msg.sender], "caller not allowed");
        _;
    }

    function addBundle(Bundle memory bundle) public onlyAllowed {
        internal_addBundle(bundle);

        // Note: bundle already includes profit, does not have to be re-calculated
        publish("bundles", abi.encode(bundle));
    }

    function getBundlesByHeight(uint256 height) public onlyAllowed returns (bool found, Bundle[] memory bundles) {
        bytes memory c_bundles_raw = get(string(abi.encodePacked("bundles-", height)));
        if (c_bundles_raw.length == 0) {
            return (false, bundles);
        }

        bytes32[] memory c_bundles = abi.decode(c_bundles_raw, (bytes32[]));
        bundles = new Bundle[](c_bundles.length);
        for (uint i = 0; i < c_bundles.length; i++) {
            bytes memory bundle_raw = get(string(abi.encodePacked("bundle-", c_bundles[i])));
            if (bundle_raw.length > 0) {
                bundles[i] = abi.decode(bundle_raw, (Bundle));
            } else {
                // wat do?
            }
        }
    }

    function internal_addBundle(Bundle memory bundle) internal {
        // TODO: check if bundle is already present!

        bytes32 bundleHash = keccak256(abi.encode(bundle));
        set(string(abi.encodePacked("bundle-", bundleHash)), abi.encode(bundle));

        // Updates bundle by height index
        bytes32[] memory n_bundles;
        bytes memory c_bundles_raw = get(string(abi.encodePacked("bundles-", bundle.height)));
        if (c_bundles_raw.length > 0) {
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

        set(string(abi.encodePacked("bundles-", bundle.height)), abi.encode(n_bundles));
    }

    // Call on each kettle to queue synchronization messages (per kettle)
    function subscribe() external {
        subscribe("bundles");
    }

    // Call on each kettle to process synchronization messages
    // Returns how many messages were processed
    function synchronize(uint maxMsgs) external returns (uint) {
        for (uint i = 0; i < maxMsgs; i++) {
            bytes memory raw_message = get_message("bundles");
            if (raw_message.length == 0) {
                // queue empty
                return i;
            }

            Bundle memory bundle = abi.decode(raw_message, (Bundle));
            internal_addBundle(bundle);
        }

        return maxMsgs;
    }
}
