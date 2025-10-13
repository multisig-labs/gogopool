
# GoGoPool Agentic Coding Rules

This file provides rules and guidelines for AI coding agents working in the GoGoPool repository.

## Commands

- **Build:** `just build`
- **Test:** `just test`
- **Test a specific contract:** `just test contract="MyContract"`
- **Test a specific test:** `just test test="myTest"`
- **Lint:** `just solhint`
- **Static Analysis:** `slither . 	--filter-paths "(lib/|utils/|openzeppelin|ERC)"`

## Code Style

### Solidity

- **Compiler Version:** Use `0.8.17`.
- **Formatting:** Follow the style in existing files.
- **Naming Conventions:**
    - Contracts: `PascalCase`
    - Functions: `camelCase`
    - Variables: `camelCase`
    - Constants: `UPPER_CASE_SNAKE_CASE`
- **Error Handling:** Use `require` and `revert` with descriptive error messages.

### Imports

- Import contracts directly, e.g., `import "../interface/IStaking.sol";`.

### General

- No inline comments.
- Keep functions small and focused.
- Add newlines at the end of every file.


