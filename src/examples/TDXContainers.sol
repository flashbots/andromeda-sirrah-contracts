pragma solidity ^0.8.13;

import "../crypto/secp256k1.sol";
import "../crypto/encryption.sol";
import "../KeyManager.sol";

struct ContainerConfig {
    uint version;
    /* type? */
    bytes32 imageHash;
    string[] containerArgs;
    /* container features */
    /* vm features */
    /* hardware stuff */
    /* maybe required measurement */
}

contract TDXContainers {
    address owner;
    KeyManager_v0 keymgr;

    /* TODO: instead require measurement is one of expected */
    bytes32 quoteMeasurementHash;
    bytes hostPubkey; // Passed in with quote

    /* TODO (maybe): verify certificate onchain against a root */
    string public pckCertPem;
    string public pckCrlPem;
    string public tcbInfo;
    string public qeIdentity;

    /* Maps keccak256(ContainerConfig) -> ContainerConfig */
    mapping(bytes32 => ContainerConfig) public pendingContainers;
    mapping(bytes32 => ContainerConfig) public approvedContainers;

    /* Maps keccak256(keccak256(ContainerConfig), msg.sender) -> ContainerConfig */
    mapping(bytes32 => ContainerConfig) public runningContainers;

    constructor(KeyManager_v0 _keymgr, string memory _pckCertPem, string memory _pckCrlPem, string memory _tcbInfo, string memory _qeIdentity) {
        owner = msg.sender;
        keymgr = _keymgr;

        /* TODO: should we allow more than one pck? */
        pckCertPem = _pckCertPem;
        pckCrlPem = _pckCrlPem;

        /* TODO: allow more than one tcbInfo */
        tcbInfo = _tcbInfo;

        qeIdentity = _qeIdentity;

        /* TODO (maybe): configure ca chain (root ca & crl, pck chain) */
    }

    function onchain_onboardHost(bytes32 _quoteMeasurementHash, bytes memory _hostPubkey, bytes memory att) external {
        require(msg.sender == owner);

        require(quoteMeasurementHash == bytes32(0)); // Only once
        require(keymgr.verify(address(this), keccak256(abi.encodePacked("hPub", _hostPubkey, "qM", _quoteMeasurementHash)), att));

        quoteMeasurementHash = _quoteMeasurementHash;
        hostPubkey = _hostPubkey;

        /* TODO: mark start/restart of the host */
        /* TODO: mark all containers stopped */
    }

    /* Hash of the pubkey passed in is expected to be in rtmr3 */
    function offchain_onboardHost(bytes memory quote, bytes memory _hostPubkey) external returns (bytes32, bytes memory, bytes memory) {
        require(msg.sender == owner);

        require(quoteMeasurementHash == bytes32(0)); // Only once

        bytes1 quote_version = quote[0];
        bytes memory quoteMeasurement = new bytes(144);
        bytes1[48] memory rtmr3;
        if (quote_version == 0x04) {
            for (uint i = 184; i < 184+48; i++) { /* mrTd */
                quoteMeasurement[i-184] = quote[i];
            }
            for (uint i = 376; i < 376+144; i++) { /* rtmr 0-2 */
                quoteMeasurement[i+32-376] = quote[i];
            }
            for (uint i = 376+144; i < 376+144+48; i++) {
                rtmr3[i-376-144] = quote[i];
            }
        } else if (quote_version == 0x05) {
            /* TODO: check body type (doesnt matter for now) */
            for (uint i = 184+6; i < 184+6+48; i++) { /* mrTd */
                quoteMeasurement[i-184-6] = quote[i];
            }
            for (uint i = 376+6; i < 376+6+144; i++) { /* rtmr 0-2 */
                quoteMeasurement[i+32-376-6] = quote[i];
            }
            for (uint i = 376+6+144; i < 376+6+144+48; i++) {
                rtmr3[i-376-144-6] = quote[i];
            }
        } else revert("unsupported quote version");

        bytes32 _quoteMeasurementHash = keccak256(quoteMeasurement);
        /* TODO: verify measurements are as expected! */
        /* TODO: require(_quoteMeasurementHash == _expectedMeasurement); */

        bytes32 hostPubkeyHash;
        assembly {
            hostPubkeyHash := mload(add(rtmr3, 32))
        }
        require(hostPubkeyHash == keccak256(_hostPubkey));

        keymgr.Suave().verifyTDXDCAPQuote(quote, pckCertPem, pckCrlPem, tcbInfo, qeIdentity);

        return  (_quoteMeasurementHash, _hostPubkey, keymgr.attest(keccak256(abi.encodePacked("hPub", _hostPubkey, "qM", _quoteMeasurementHash))));
    }

    /* Offchain. Decrypts data using keymgr's key and encrypts it to host's pubkey */
    function reencryptToHostKey(bytes memory ciphertext /* TODO: should we also require a specific quote measurement? */) external returns (bytes memory) {
        bytes memory plaintext = PKE.decrypt(keymgr.derivedPriv(), ciphertext);
        return PKE.encrypt(hostPubkey, keymgr.Suave().localRandom(), plaintext);
    }

    event NewContainerRequested(bytes32, ContainerConfig);
    function submit(ContainerConfig calldata container) external {
        bytes32 id = keccak256(abi.encode(container));
        pendingContainers[id] = container;
        emit NewContainerRequested(id, container);
    }

    function approve(bytes32 id) external {
        require(msg.sender == owner);

        ContainerConfig memory container = pendingContainers[id];
        if (container.imageHash == bytes32(0)) revert("unknown container");

        approvedContainers[id] = container;
    }

    event StartContainerRequested(bytes32, ContainerConfig);
    function start(bytes32 id) external {
        bytes32 runtimeId = keccak256(abi.encodePacked(id, msg.sender));
        ContainerConfig memory container = runningContainers[runtimeId];
        if (container.imageHash != bytes32(0)) {
            emit StartContainerRequested(runtimeId, container);
            return;
        }

        container = approvedContainers[id];
        if (container.imageHash != bytes32(0)) {
            emit StartContainerRequested(runtimeId, container);
            runningContainers[runtimeId] = container;
            return;
        }

        revert("unknown container");
    }

    event StopContainerRequested(bytes32, ContainerConfig);
    function stop(bytes32 id) external {
        bytes32 runtimeId = keccak256(abi.encodePacked(id, msg.sender));

        ContainerConfig memory container = runningContainers[runtimeId];
        if (container.imageHash != bytes32(0)) {
            emit StopContainerRequested(runtimeId, container);
            delete runningContainers[runtimeId];
            return;
        }

        container = approvedContainers[id];
        if (container.imageHash != bytes32(0)) {
            emit StopContainerRequested(runtimeId, container);
            return;
        }

        revert("unknown container");
    }

    function heartbeat() external {
        require(msg.sender == owner);

        /* TODO: require a volatile, only known to the TDX secret */
        /* for example: sign(block hash) with a random, volatile key pair */
        /* Make sure host restart (and container stop/restart) is noted */

        /* TODO: allow customization here, say a contract per container that pays and checks if it should still be running */
    }

    function claimDead() external {
        /* TODO: check last heartbeat, if too old refund everyone and mark all containers stopped */
    }
}
