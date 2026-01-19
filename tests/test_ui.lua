local lu = require('tests.luaunit')
local ui = require('modules.ui')
local mp = require('mp')

TestUI = {}

function TestUI:setUp()
    mp._messages = {}
end

function TestUI:test_show_message()
    ui.show_message("Test Message")
    lu.assertEquals(#mp._messages, 1)
    lu.assertEquals(mp._messages[1], "Test Message")
end

function TestUI:test_show_message_with_duration()
    ui.show_message("Test Message", 5)
    -- The duration is passed to osd_message but our mock just stores the msg.
    -- We could update mock to store duration too if strict testing needed.
    lu.assertEquals(#mp._messages, 1)
    lu.assertEquals(mp._messages[1], "Test Message")
end
