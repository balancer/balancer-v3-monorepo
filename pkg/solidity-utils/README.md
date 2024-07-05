# <img src="../../logo.svg" alt="Balancer" height="128px">

# Balancer V3 Solidity Utilities

This package contains Solidity utilities and libraries used when developing Balancer V3 contracts. Many design decisions and trade-offs have been made in the context of Balancer V3's requirements and constraints (such as reduced bytecode size), which may make these libraries unsuitable for other projects.

## Licensing

Most of the Solidity source code is licensed under the GNU General Public License Version 3 (GPL v3): see [`LICENSE`](../../LICENSE).

### Exceptions

- The [`LogExpMath`](./contracts/math/LogExpMath.sol) contract is licensed under the MIT License.
