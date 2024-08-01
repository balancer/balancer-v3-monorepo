## Ports from OpenZeppelin Contracts

Files in this directory are based on the [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) library, and as such are licensed under the MIT License: see [LICENSE](./LICENSE).

Most of the modifications fall under one of these categories:

- removal of functions unused in Balancer V3 source code
- modification or addition of functionality to reduce bytecode size or gas usage (see `EnumerableSet`, `EnumerableMap`)
- addition of selected files from unreleased code to support new features (see `SlotDerivation`, `StorageSlotExtension`)

Non-trivial modifications in this last category have associated source code comments that explain the changes and motivation.
