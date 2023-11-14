## Andromeda Key Manager Contracts

### Mockup in forge of precompiles used by Andromeda.

See [./src/AndromedaForge.sol](./src/AndromedaForge.sol)
  
 - `Suave.localRandom`	uses [./ffi/local_random.sh](ffi/local_random.sh) to sample 32 bytes from `/dev/urandom`.
 - `Suave.attestSgx` provide remote attestations, here mocked just using an insecure hmac. Note that `Suave.verifySgx` could be pure Solidity and does not need to be a precompile 
 - `Suave.volatile{Get/Set}` provide ephemeral storage, local to *this kettle process*. If the kettle restarts, this resets too. Persistence using sealed files will be dealt with in a separate issue. To mock volatile storage in Forge, we simply use environment variables (through `vm.setEnv`, `vm.envOr`). In a test environment, we can invoke `switchHost` to separate these.
  
### Key manager example based on Secret Network

  See [./src/KeyManagerSN.sol](./src/KeyManagerSN.sol). A [test scenario](./test/KeyManagerSN.t.sol) goes along with the following:
  
  1. **Bootstrapping.**
      - *1a. Off-chain*. One node goes first. It uses `Suave.localRandom()` to generate a key `xPriv`, and stores it locally with `Suave.volatileSet()`.
      - *1b. On-chain*. The resulting public key `xPub` is stored on chain after checking the remote attestation.
  2. **New Node registers.**
      - *2a. Off-chain*. A new node register. It uses `Suave.localRandom()` to generate a temporary key `myPriv`, and stores it locally with `Suave.volatileSet()`.
      - *2b. On-chain*. The resulting temporary key `myPub` is stored on chain after checking the remote attestation.
  3. **Existing node onboards the new node.**
      - *3a. Off-chain at the existing node*. An existing node fetches `xPriv` from volatile storage, and encrypts it to the new node's `myPub`.
      - *3b. On-chain*. This isn't necessary, but the `ciphertext` can be posted on-chain.
      - *3c. Off-chain at the new node.* The new node decrypts `xPriv` and stores in volatile storage.

The libraries in [./src/crypto/](./src/crypto/) include Solidity implementations of
  - public key encryption using `bn128` (Byzantium opcodes), along with the following symmetric encryption
  - symmetric encryption using `keccak` as a block cipher
  - deriving an Ethereum address from a private key

These come from searching libraries but these haven't been carefully vetted. They should be easily replaceable though.

## Usage

Relies on https://getfoundry.sh/

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test --ffi
```
