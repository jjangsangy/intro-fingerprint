local lu = require('tests.luaunit')
local state = require('modules.state')

TestState = {}

function TestState:setUp()
    -- Reset state
    state.scanning = false
    state.current_scan_token = nil
end

function TestState:test_initial_state()
    lu.assertFalse(state.scanning)
    lu.assertNil(state.current_scan_token)
end

function TestState:test_state_mutation()
    state.scanning = true
    lu.assertTrue(state.scanning)

    state.current_scan_token = 123
    lu.assertEquals(state.current_scan_token, 123)
end
