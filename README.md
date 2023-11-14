## Andromeda Key Manager Contracts

### Mockup in forge of precompiles used by Andromeda.

See [./src/AndromedaForge.sol](./src/AndromedaForge.sol)
  
 - localRandom	uses `ffi/local_random.sh` to sample 32 bytes from `urandom`.
 - sgxAttest/sgxVerify
 - volatileGet/Set.
  
- Key manager example based on Secret Network

  See [./src/KeyManagerSN.sol](./src/KeyManagerSN.sol)

## Usage

Relies on https://getfoundry.sh/

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```
