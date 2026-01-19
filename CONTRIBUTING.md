# Contributing to Intro Fingerprint

Thank you for your interest in contributing to **Intro Fingerprint**! This document provides guidelines and instructions for setting up your environment, following our coding standards, and submitting changes.

## 🚀 Getting Started

### Prerequisites

*   **Lua Environment**: [LuaJIT](https://luajit.org/) (2.1+) or Lua 5.1.
*   **Python**: Required for the pre-commit framework. We recommend using [uv](https://github.com/astral-sh/uv).
*   **Linter**: [Lua Language Server](https://luals.github.io/) must be available in your PATH (`lua-language-server`).
*   **FFmpeg**: Must be available in your PATH for integration testing.

### Installation

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/jjangsangy/intro-fingerprint.git
    cd intro-fingerprint
    ```

2.  **Set up Pre-commit Hooks**:
    We use `pre-commit` to ensure tests pass and code is linted before every commit.
    ```bash
    # Install pre-commit (using uv)
    uv tool install pre-commit

    # Install the git hooks
    pre-commit install
    ```

## 🛠️ Development Standards

We strictly follow the practices defined in our project rules. Please ensure your code adheres to these standards.

### Architecture
*   **Modular Design**: All core logic resides in `modules/`.
*   **Orchestrator**: `main.lua` acts only as the entry point and orchestrator. It should not contain heavy logic.
*   **Single Responsibility**: Each module should focus on one logical area (e.g., `audio.lua`, `video.lua`).

### Coding Style
*   **Local Table Pattern**: Every module file **MUST** start with `local M = {}` and end with `return M`. All exports must be attached to `M`.
*   **Strict Locals**: Use `local` for every variable and function. **Do NOT** pollute the global environment.
*   **Imports**: Use dot-notation for requirements (e.g., `local utils = require "modules.utils"`).

### Performance & Async
*   **Non-Blocking I/O**: **ALWAYS** use `mp.command_native_async` or `mp.utils.subprocess` (with async callback). Never block the main MPV thread.
*   **FFI & Fallbacks**: Prefer `ffi` for computationally intensive tasks but **ALWAYS** provide a pure Lua fallback for compatibility.

### Documentation
All functions must include LuaDoc-style documentation:
```lua
--- Brief description of function
-- @param param_name type - description
-- @return type - description of return value
-- @note Any important implementation details or side effects
function M.my_function(param_name)
    -- implementation
end
```

## 🧪 Testing

We use `luaunit` for testing. The `mp` API is mocked, allowing tests to run without an MPV instance.

### Running Tests
Run the entire suite from the project root:
```bash
lua tests/run_tests.lua
```

### Adding Tests
1.  Create a test file: `tests/test_<module>.lua`.
2.  Register it in `tests/run_tests.lua` by adding: `require('tests.test_<module>')`.
3.  Implement tests using `luaunit` assertions:
    ```lua
    local lu = require('tests.luaunit')
    local my_module = require('modules.my_module')

    TestMyModule = {}
    function TestMyModule:test_feature()
        lu.assertEquals(my_module.fn(), expected)
    end
    ```

## 🔍 Pre-commit Hooks

Our pre-commit configuration (`.pre-commit-config.yaml`) enforces:
1.  **Tests**: Runs `lua tests/run_tests.lua`.
2.  **Linting**: Runs `lua-language-server` to check for errors and warnings.

You can run these checks manually at any time:
```bash
pre-commit run --all-files
```

## 📝 Submitting Changes

1.  Create a new branch for your feature or fix.
2.  Ensure all tests pass and the linter is happy.
3.  Submit a Pull Request with a clear description of your changes.
