# Testing Guide

## Running Tests
Run from the project root:
```bash
luajit tests/run_tests.lua
```

Also ensure it works on pure lua 5.1
```bash
lua tests/run_tests.lua
```

## Adding Tests
1.  **Create File**: `tests/test_<module>.lua`
2.  **Register**: Add `require('tests.test_<module>')` to `tests/run_tests.lua`
3.  **Implement**:
    ```lua
    local lu = require('tests.luaunit')
    local my_module = require('modules.my_module')

    TestMyModule = {}
    function TestMyModule:test_feature()
        lu.assertEquals(my_module.fn(), expected)
    end
    ```

## Mocking `mp` API
The `mp` API is fully mocked in `tests/mocks.lua`.
- **Properties**: Use `mp.set_property(name, val)` in tests to setup state.
- **Commands**: `mp.command_native` returns success by default.
- **Subprocess**: `mp.utils.subprocess` returns `{status=0}` by default.
