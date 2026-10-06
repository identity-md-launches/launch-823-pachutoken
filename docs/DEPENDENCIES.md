# Vendored dependencies

All required Solidity dependencies are ordinary files under `lib/`. No package
installation, submodule, or network access is required to compile or test once
Foundry and the pinned Solidity 0.8.26 compiler are available.

| Dependency | Release | Included files | License |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | v5.0.2 | ERC20.sol and its four transitive Solidity imports | MIT, `lib/openzeppelin-contracts/LICENSE` |
| Forge Standard Library | v1.9.7 | Complete upstream `src/` tree (test dependency only) | MIT / Apache-2.0, included in `lib/forge-std/` |

Upstream files are unmodified. Only the required OpenZeppelin source subset is
vendored; this project does not depend on unrelated extensions or upgrade tools.

Source archives and SHA-256 checksums:

- `https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2`
  — `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`
- `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7`
  — `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`
