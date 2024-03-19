# Andromeda Sirrah Demos

This directory contains a demo webapp for the [Timelock contract](../src/examples/Timelock.sol).  
You can see the live demo at `http://timelock.sirrah.suave.flashbots.net:5173`.  

## Building and running the demos

1. Make sure you have `bun` installed (`npm i --global bun`)
2. Run `npm install` in the parent directory
3. Run `bun install` instead of the usual `npm install` in the demos directory
4. Build the demo with `bun vite build <demo>` (`bun run build`)
5. Run the demo with `bun vite <demo>` (`bun run timelock` or `bun run confstore`)

Running the Timelock demo webapp requires that you have the Timelock contract address configured in the [../deployment.json](../deployment.json) file like so:
```
  "ARTIFACTS": {
    "out/Timelock.sol/Timelock.json": {
      "address": "0x6858162E579DFC66a623AE1bA357d67BF026dDD6",
      "constructor_args": []
    },
    "out/RedisConfidentialStore.sol/BundleConfidentialStore.json": {
      "address": "0xF1b9942f1DBf1dD9538FC2ee8e2FC533b7070366",
      "constructor_args": []
    }
  }
```

If you want to build and deploy the demo contracts from scratch, see the parent [../README.md](../README.md).  

## Signing chain transactions

The demo will sign chain transactions with either the raw private key (if one is provided through [../deployment.json](../deployment.json)), or with MetaMask.  
> [!WARNING]
> **DO NOT PUT YOUR PRIVATE KEY IN THE DEPLOYMENT FILE IF YOU INTEND TO EXPOSE THE WEBAPP.** Since this is a React app, all of the contents of imported files could be accessible to whoever connects to your application. If you intend to expose the demo, rely on MetaMask instead.
