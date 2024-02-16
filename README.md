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

This returns new random bytes each time it is called, sampled using the `RDRAND` x86 instruction.

- *Process storage*

```solidity
function volatileSet(bytes32 tag, bytes32 value) external;
function volatileGet(bytes32 tag) external returns(bytes32 value);
```

This provides a key value storage. Each caller has its own isolated storage. If a message call reverts, it will *not* undo the side effects of `volatileSet`. All this storage is cleared each time the process restarts.

- *Persistent storage*

```solidity
function sealingKey() view external;
```
This provides a persistent key. For each caller, each MRENCLAVE on each CPU gets its own one of these. This is used so the enclave can store an encrypted file and retrieve it later if the process restarts.

- *Remote attestation*

 ```solidity
function attestSgx(bytes32 appData) external returns (bytes memory att);
function verifySgx(address caller, bytes32 appData, bytes memory att) external view returns (bool);`
```

This produces evidence that the `appData` was requested by the `caller`. The verification routine is pure Solidity, and does not require any special precompiles.

- *Services manager*

// TODO

## Implementations
We provide three implementations of the Andromeda interface:

1. A forge mockup environment. This is sufficient for logical testing of smart contracts. [./src/AndromedaForge.sol](./src/AndromedaForge.sol)
2. A remote environment using actual remote attestations, computed via a remote service (dummy attester service) [./src/AndromedaRemote.sol](./src/AndromedaRemote.sol)
3. Invoke the actual the precompiles recognized by the Andromeda EVM in separate repository, [suave-andromeda-revm](https://github.com/flashbots/suave-andromeda-revm/).

To reiterate, the forge development environment here (implementations 1 and 2) does NOT require any use of SGX, so you can develop on any machine (even on TEE-level components like a Key Manager and TCB recovery handling).

## Speedrunning a Second Price auction

Here's the motivating scenario to go along with the blogpost: Looking at [./src/examples/SpeedrunAuction.sol:LeakyAuction](./src/examples/SpeedrunAuction.sol), we can see a second price auction in plain ordinary Solidity. But, due to a lack of privacy, this is vulnerable to griefing through MEV.

The point of this demo is to solve this problem using the Andromeda precompiles. See: [./src/examples/Auction.sol:SealedAuction](./src/examples/Auction.sol)

## Key Manager

The "speedrun" was a little unsatisfying because you have to bootstrap a new key each time you carry out an auction. Instead, we want to have a singletone Key Manager that encapsulates a single bootstrapping ceremony, and thereafter *many applications* as well as *many separate kettles* can provide confidential coprocessing service. The proposed key manager has the following features:

- Verification of a raw SGX attestation (expensive in Solidity gas) only needs to occur once per Kettle. After initial registration, ordinary digital signatures can be used instead. Much cheaper.
- Multiple Kettles can join. Newly registered Kettles receive a copy of the key from existing Kettles that already have it
- A single instance of the Key Manager contract can be used by other contracts.

This is still a simplified strawman example, as it does not support upgrading the enclave, revoking keys, etc. This is meant as a starting point, and those ideas can be explored in Solidity.

## Timelock encryption demo

As one demo, we include a sample application in the form of a timelock decryption service.
The code is at [./src/examples/Timelock.sol:Timelock](./src/examples/Timelock.sol)
and the smart contract is found on the Rigil test network [https://explorer.rigil.suave.flashbots.net/address/0x6858162E579DFC66a623AE1bA357d67BF026dDD6](https://explorer.rigil.suave.flashbots.net/address/0x6858162E579DFC66a623AE1bA357d67BF026dDD6).

The application is very simple: messages are encrypted to the public key of the contract. A TEE kettle can only decrypt them only after the light client reports that a deadline has passed on the blockchain. 

The frontend is hosted at https://timelock.sirrah.suave.flashbots.net/
You'll need to point your web3 browser extension like Metamask to [point to a Rigil endpoint](https://github.com/flashbots/suave-specs/tree/main/specs/rigil). If you don't have Rigil testnet coins you can get some at [faucet.rigil.suave.flashbots.net](https://faucet.rigil.suave.flashbots.net).

## Confidential bundle store demo

// TODO

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

## Rigil

If you want to build and deploy only some of the contracts, here are ones predeployed to Rigil.

1. Contracts

In [deployment.json] change the `ADDR_OVERRIDES` to include:

```
  "ADDR_OVERRIDES": {
    "out/SigVerifyLib.sol/SigVerifyLib.json": "0xed16804dB4D00A61e85569362ac10ef66126B13e",
    "out/Andromeda.sol/Andromeda.json": "0x76832d4d9823eCD154598Ce2969D5C4e794E84c4"
  }
```

2. Demo apps

If you want to use predeployed `Timelock` demo, one is available on Rigil. Include the following in the `ADDR_OVERRIDES`:

```
  "ADDR_OVERRIDES": {
    "out/Timelock.sol/Timelock.json": "0x6858162E579DFC66a623AE1bA357d67BF026dDD6",
    "out/RedisConfidentialStore.sol/BundleConfidentialStore.json": "0xF1b9942f1DBf1dD9538FC2ee8e2FC533b7070366"
  }
```

> [!WARNING]
> The addresses will change, so don't depend on them too much. This is intended for quick prototyping rather than something that is highly available.


### Rigil kettle

If you don't want to run a kettle yourself, you can always connect to the development TEE kettle at https://kettle.sirrah.suave.flashbots.net.

## License

The code in this project is free software under the [MIT license](LICENSE).
