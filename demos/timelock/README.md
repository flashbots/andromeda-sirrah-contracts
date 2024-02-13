# Timelock demo WebApp

This directory contains a demo webapp for the [Timelock contract](../src/examples/Timelock.sol).  
You can see the live demo at `http://timelock.sirrah.suave.flashbots.net:5173`.  

## Building and running the Timelock webapp

1. Make sure you have `bun` installed (`npm i --global bun`) and run `bun install` instead of the usual `npm install`
2. Run `npm install` in the parent directory
3. Build the webapp with `bun vite build` (alternatively `npm run build`)
4. Run the webapp with `bun vite` (alternatively `npm run dev`)

Running the Timelock demo webapp requires that you have the Timelock contract address configured in the [../deployment.json](../deployment.json) file like so:
```
  "ADDR_OVERRIDES": {
    "out/Timelock.sol/Timelock.json": "0x6858162E579DFC66a623AE1bA357d67BF026dDD6"
  }
```

If you want to build and deploy the Timelock contract from scratch, see the parent [../README.md](../README.md).  

## Signing chain transactions

The demo will sign chain transactions with either the raw private key (if one is provided through [../deployment.json](../deployment.json)), or with MetaMask.  
> [!WARNING]
> **DO NOT PUT YOUR PRIVATE KEY IN THE DEPLOYMENT FILE IF YOU INTEND TO EXPOSE THE WEBAPP.** Since this is a React app, all of the contents of imported files could be accessible to whoever connects to your application. If you intend to expose the demo, rely on MetaMask instead.
