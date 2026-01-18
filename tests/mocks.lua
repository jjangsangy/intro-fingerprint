local M = {}

function M.create_mp()
    local mp = {}

    -- State for properties and messages
    mp._properties = {}
    mp._messages = {} -- Store OSD messages
    mp._log = {} -- Store log messages
    mp._commands = {} -- Store command calls
    mp._command_returns = {} -- Mock returns for specific commands

    mp.msg = {
        info = function(...) table.insert(mp._log, {"info", ...}) end,
        warn = function(...) table.insert(mp._log, {"warn", ...}) end,
        error = function(...) table.insert(mp._log, {"error", ...}) end,
        verbose = function(...) table.insert(mp._log, {"verbose", ...}) end,
    }

    mp.utils = {
        join_path = function(p1, p2)
            local sep = package.config:sub(1,1)
            return p1 .. sep .. p2
        end,
        subprocess = function(t)
            table.insert(mp._commands, {name="subprocess", args=t.args})
            if mp._command_returns["subprocess"] then
                if type(mp._command_returns["subprocess"]) == "function" then
                    return mp._command_returns["subprocess"](t)
                end
                return mp._command_returns["subprocess"]
            end
            return {status = 0, stdout = "", stderr = ""}
        end,
        get_user_path = function(p) return p end,
    }

    mp.options = {
        read_options = function(table, identifier, on_update)
            return
        end,
    }

    mp.get_property = function(name)
        return mp._properties[name]
    end

    mp.get_property_number = function(name)
        return tonumber(mp._properties[name])
    end

    mp.get_property_bool = function(name)
        return not not mp._properties[name]
    end

    mp.set_property = function(name, val)
        mp._properties[name] = val
    end

    mp.get_time = function()
        return os.clock()
    end

    mp.osd_message = function(msg, duration)
        table.insert(mp._messages, msg)
    end

    mp.command_native = function(cmd)
        table.insert(mp._commands, cmd)
        -- Check if we have a mocked return for this command type
        if cmd.name and mp._command_returns[cmd.name] then
             return mp._command_returns[cmd.name]
        end
        return {status=0}
    end

    mp._async_callbacks = {}

    mp.command_native_async = function(cmd, fn)
        table.insert(mp._commands, cmd)
        if fn then
            -- Store callback to be called later
            table.insert(mp._async_callbacks, {
                fn = fn,
                cmd = cmd
            })
        end
        return 1 -- Token
    end

    mp._process_async_callbacks = function()
        while #mp._async_callbacks > 0 do
            local item = table.remove(mp._async_callbacks, 1)
            local res = {status=0, stdout="", stderr=""}

            -- Check return value (table or function)
            local ret_val = nil
            if item.cmd.name and mp._command_returns[item.cmd.name] then
                ret_val = mp._command_returns[item.cmd.name]
            end
            -- Also check subprocess return if command is subprocess
            if item.cmd.name == "subprocess" and mp._command_returns["subprocess"] then
                ret_val = mp._command_returns["subprocess"]
            end

            if ret_val then
                if type(ret_val) == "function" then
                    res = ret_val(item.cmd)
                else
                    res = ret_val
                end
            end

            item.fn(true, res, nil)
        end
    end

    mp.abort_async_command = function(token) end
    mp.register_event = function(name, fn) end
    mp.add_key_binding = function(key, name, fn) end
    mp.observe_property = function(name, type, fn) end

    return mp
end

function M.init_preload(mp)
    package.preload['mp'] = function() return mp end
    package.preload['mp.msg'] = function() return mp.msg end
    package.preload['mp.utils'] = function() return mp.utils end
    package.preload['mp.options'] = function() return mp.options end
end

return M
