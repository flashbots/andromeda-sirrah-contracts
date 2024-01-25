> [!WARNING]
> This repository is a work in progress, and for now only functions as a showcase. This code *is not intended to secure any valuable information*.

# Andromeda Sirrah Contracts

This repository contains the smart contracts and development environment for SUAVE's intermediate programming layer, where Solidity contracts directly control SGX trusted hardware features like attestation and sealing. This also contains the code and examples that go along with the post "Sirrah: Speedrunning a TEE Coprocessor."

## Andromeda Precompiles

The Andromeda precompiles are a minimal way to add Trusted Hardware Enclaves to the Solidity environment.
The interface is defined in [./src/IAndromeda.sol](./src/IAndromeda.sol)). It basically adds four new things:

- *Sampling random bytes*.

```solidity
function localRandom() view external returns(bytes32);
```

- *Process storage*

```solidity
function volatileSet(bytes32 tag, bytes32 value) external;
function volatileGet(bytes32 tag) external returns(bytes32 value);
```

- *Persistent storage*

```solidity
function sealingKey() view external;
```

- *Remote attestation*

 ```solidity
function attestSgx(bytes32 appData) external returns (bytes memory att);
function verifySgx(address caller, bytes32 appData, bytes memory att) external view returns (bool);`
```

We provide three implementations:

1. A forge mockup environment. This is sufficient for logical testing of smart contracts. [./src/AndromedaForge.sol](./src/AndromedaForge.sol)
2. A remote environment using actual remote attestations, computed via a remote service (dummy attester service TODO) [./src/AndromedaRemote.sol](./src/AndromedaRemote.sol)
3. Actually invoke the precompile addresses recognized by the MEVM.

To reiterate, the actual implementation of these precompiles in EVM is in a [separate repository.](https://github.com/flashbots/suave-andromeda-revm/). The forge development environment here does NOT require any use of SGX, so you can develop (even on low level components like a Key Manager and TCB recovery handling) on any machine.

## Speedrunning a Second Price auction

Here's the motivating scenario to go along with the blogpost: Looking at [./src/examples/SpeedrunAuction.sol:LeakyAuction](./src/examples/SpeedrunAuction.sol), we can see a second price auction in plain ordinary Solidity. But, due to a lack of privacy, this is vulnerable to griefing through MEV.

The point of this demo is to solve this problem using the Andromeda precompiles. See: [./src/examples/Auction.sol:SealedAuction](./src/examples/Auction.sol)

## Key Manager

The "speedrun" was a little unsatisfying because you have to bootstrap a new key each time you carry out an auction. Instead, we want to have a singletone Key Manager that encapsulates a single bootstrapping ceremony, and thereafter *many applications* as well as *many separate kettles* can provide confidential coprocessing service. The proposed key manager has the following features:

- Verification of a raw SGX attestation (expensive in Solidity gas) only needs to occur once per Kettle. After initial registration, ordinary digital signatures can be used instead. Much cheaper.
- Multiple Kettles can join. Newly registered Kettles receive a copy of the key from existing Kettles that already have it
- A single instance of the Key Manager contract can be used by other contracts.

This is still a simplified strawman example, as it does not support upgrading the enclave, revoking keys, etc.

- ## Timelock encryption demo

Configure the message to a (multiple of 32-bytes) string of your choice.
This will use `cast` to encrypt it (obv this could be done locally).
Then we post the ciphertext on Rigil.
Later,

```bash
TIMELOCK=0xe06c085eebaa0b8f908E7Bc931355D681391BC8e; \
MESSAGE='ABCDE timelock test message!32xr'; \
CIPH=$(cast call --rpc-url=https://rpc.rigil.suave.flashbots.net --chain-id=16813125 $TIMELOCK "encryptMessage(string memory message, bytes32 r)returns(bytes)" "$MESSAGE" 0x$(head -c32 /dev/urandom | xxd -p -c64)); \
echo Ciphertext: $CIPH; \
cast send --legacy --rpc-url=https://rpc.rigil.suave.flashbots.net --chain-id=16813125 --private-key=$(cat privkey) $TIMELOCK "submitEncrypted(bytes)" $CIPH; \
echo Waiting for 90 seconds...; \
sleep 90; \
echo Fetching result:; \
curl http://sirrah.ln.soc1024.com/decrypt/$CIPH
```

## Usage

Relies on [Foundry](https://getfoundry.sh/) for contrats, [Python 3](https://www.python.org/downloads/) for various utilities, and [npm](https://nodejs.org/en) for automation and demo.  

For ease of use we provide the following `make` targets:
* `make build` to build contracts
* `make format` to format contracts
* `make test` to test contracts
* `make deploy` to deploy contracts
* `make configure-all-tcbinfos` to configure `Andromeda` contracts with TCBInfo from Intel
* `make bootstrap` to bootstrap a kettle for `KeyManager`
* `make onboard` to onboard a kettle to `KeyManager` from one already bootstrapped
* `make deploy-examples` to deploy `SealedAuction` and `Timelock` for use in the demo webapp
* `make test-examples` to automatically deploy and test `SealedAuction` and `Timelock` on chain

Deployed contracts are kept track of in the [deployment.json](deployment.json) file. If you want to re-deploy a contract, simply remove it from the `ADDR_OVERRIDES` section. The various deployment scripts write to the file on successful deployments.

## Rigil predeployed contracts

If you want to build and deploy only some of the contracts, here are ones predeployed to Rigil.

1. Libraries

In [foundry.toml] add the following line at the end of the file:
```
libraries = ["src/crypto/encryption.sol:SimpleEncryption:0x10296A369d68a5DCafa30fDc9a99Af3154eF3D87", "src/crypto/encryption.sol:PKE:0xD31973ab1FEf7F0010ffae5c812A88B9a046279b", "src/crypto/secp256k1.sol:Secp256k1:0x4537Ed80812cd0740170baE40BaeC0E9F1fEeB53"]
```

2. Contracts

In [deployment.json] change the `ADDR_OVERRIDES` to include:

```
  "ADDR_OVERRIDES": {
    "out/SigVerifyLib.sol/SigVerifyLib.json": "0xed16804dB4D00A61e85569362ac10ef66126B13e",
    "out/Andromeda.sol/Andromeda.json": "0x76832d4d9823eCD154598Ce2969D5C4e794E84c4"
  }
```

3. Demo apps

If you want to use predeployed `Timelock` demo, one is available on Rigil. Include the following in the `ADDR_OVERRIDES`:

```
  "ADDR_OVERRIDES": {
    "out/Timelock.sol/Timelock.json": "0x6858162E579DFC66a623AE1bA357d67BF026dDD6"
  }
```

> :warning the addresses will change, so don't depend on them too much. This is intended for quick prototyping rather than something that is highly available.


## License

The code in this project is free software under the [MIT license](LICENSE).
