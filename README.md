# Andromeda Sirrah Contracts

This repository contains the smart contracts and development environment that go along with the post "Sirrah: Speedrunning a TEE Coprocessor."

The contracts here make use of the Andromeda precompiles. The actual implementation of these in an EVM running on SGX are in a [separate repository.](https://github.com/flashbots/revm-andromeda/). The forge development environment here does NOT require any SGX.

## 01 - Sealed second price auction application

The main production of this demo is a sealed bid auction
Looking at [./src/01-Auction.sol:LeakyAuction](./src/01-Auction.sol), we can see a second price auction in Solidity. But due to a lack of privacy, it is vulnerable to griefing by validators.

The fixed auction making use of [./src/01-Auction.sol:SealedAuction](./src/01-Auction.sol)

## 02 - Example Key Manager 

The approach to key management was a little simplistic. There's only a single. 
So, we next show how to extend this.

- Verification of a raw SGX attestation (expensive in Solidity gas) only needs to occur once per Kettle. After initial registration, ordinary digital signatures can be used instead. Much cheaper.
- Multiple Kettles can join. Newly registered Kettles receive a copy of the key from existing Kettles that already have it
- A single instance of the Key Manager contract can be used by other contracts.

## Forge Mockup of Andromeda precompiles.

This project is built on the low-level Andromeda precompiles: (See [./src/IAndromeda.sol](./src/IAndromeda.sol)):
- *Sampling random bytes*.
```solidity
function localRandom() view external returns(bytes32);
```
- *Process storage*
```solidity
function volatileSet(bytes32 tag, bytes32 value) external;
function volatileGet(bytes32 tag) external returns(bytes32 value);
```
- *Remote attestation*
 ```solidity
function attestSgx(bytes32 appData) external returns (bytes memory att);
function verifySgx(address caller, bytes32 appData, bytes memory att) external view returns (bool);`
```

Note that `verifySgx` is implemented in pure Solidity and does not require a precompile.
Sampling randomness requires the `ffi` interface (see [./ffi/local_random.sh](./ffi/local_random.sh)).

There are two instantiations of this interface:
- *Using mock attestations.* No dependency required. [./src/AndromedaForge.sol](./src/AndromedaForge.sol)
- *Using a remote attestation service.* This requires Python and the `eth_abi` in order to fetch from a remote website. [./src/AndromedaRemote.sol](./src/AndromedaRemote.sol) 

## Usage

Relies on https://getfoundry.sh/

### Requires python
```shell
pip install -r requirements.txt
```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test --ffi
```

### Format

```shell
$ forge fmt .
```

## Timelock encryption demo

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