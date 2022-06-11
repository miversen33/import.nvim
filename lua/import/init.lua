--- Safely wraps the traditional require function that lua uses for importing modules
--- Use in place of "require".

local log_timestamp_format = '%Y-%m-%d %H:%M:%S'
local M = {}

M.import_statuses = {
    failures = {},
    successes = {},
    info = {},
}

M.user_opts = {}

--- Use in place of "require"
--- @param path string
---     The path to import, this should be exactly what you would pass to require
--- @param success_callback function
---     Optional: If provided, this function will be called on a successfull import of
---     the provided "path". This function will be provided the imported module as
---     its single parameter.
---     Note: This is saved for calling later on reload
---     EG: success_callback(imported_module)
--- @return nil
---
--- Examples
--- require("import.nvim") -- require the import package to get the ability to use its import functionality
--- import("lualine", function(lualine) lualine.setup{ "do your module setup here" } end)
--- import("cmp", function(cmp) cmp.setup{ "do your module setup here" } end)
--- import("netman") -- This module doesn't require setup so you dont need to specify it
function M.import(path, success_callback)
    -- TODO: (Mike) I am unsure if this is the best way to do handle an existing import or not?
    -- I dont think I want to fail as importing on an import is completely valid.
    if package.loaded[path] then
        if success_callback then success_callback(package.loaded[path]) end
        return
    end
    -- TODO: (Mike) Consider making the import async?
    local print_logs = {}
    local error_logs = {}
    local replay_log = {}
    local _print = print
    local _error = error
    local log_format = '%s - [%s] %s'
    -- print/error shim function to collect statements sent to both
    local print_shim = function(...)
        local print_log = string.format(log_format, path, os.date(log_timestamp_format), table.concat({...}))
        table.insert(print_logs, print_log)
        if M.user_opts.import_enable_better_printing then
            table.insert(replay_log, {level='print', log=print_log})
        else
            table.insert(replay_log, {level='print', log=...})
        end
    end
    -- redirect errors to print to avoid breaking import
    local error_shim = function(...)
        local error_log = string.format('ERROR: ' .. log_format, path, os.date(log_timestamp_format), table.concat({...}))
        table.insert(error_logs, error_log)
        if m.user_opts.import_enable_better_printing then
            table.insert(replay_log, {level='error', log=error_log})
        else
            table.insert(replay_log, {level='error', log=...})
        end
    end
    -- global shenanigans
    _G.print = print_shim
    _G.error = error_shim
    local start_time = vim.loop.hrtime()
    local status, module_return = pcall(require, path)
    local duration = vim.loop.hrtime() - start_time
    -- global shenanigans part 2, electric boogaloo
    _G.print = _print
    _G.error = _error
    -- Since we silenced log output above, lets replay the print events to neovim outside
    -- pcall. We are doing it this way since apparently prints dont always fire
    -- in neovim during a require, but they _will_ fire during a pcall.
    -- Thus to replicate the behavior, we are replaying the events to let neovim
    -- do whatever wild neovims do
    for _, log_info in ipairs(replay_log) do
        print(log_info.log)
    end
    local message = nil
    if not status then
        -- Import failed 😡
        message = module_return
        M.import_statuses.failures[path] = 1
    else
        -- Import was a success 😀
        M.import_statuses.successes[path] = 1
        if success_callback then
            local callback_status, _ = pcall(success_callback, module_return)
            if not callback_status then
                -- Callback failed 😡
                error_shim(_)
                M.import_statuses.successes[path] = nil
                M.import_statuses.failures[path] = 1
            end
        end
    end
    M.import_statuses.info[path] = {import_message=message, import_time=duration, print_logs=print_logs, error_logs=error_logs, success_callback=success_callback}
end

--- Returns the number of failed imports
function M.get_failure_count()
    local count = 0
    for _, _ in pairs(M.import_statuses.failures) do
        count = count + 1
    end
    return count
end

--- Returns the number of successful imports
function M.get_success_count()
    local count = 0
    for _, _ in pairs(M.import_statuses.successes) do
        count = count + 1
    end
    return count
end

--- Returns table (array) of modules (strings) that were imported (successfully or otherwise)
function M.get_imported_modules()
    local results = {}
    for path, _ in pairs(M.import_statuses.info) do
        table.insert(results, path)
    end
    table.sort(results, function(a, b) return a:upper() < b:upper() end)
    return results
end

--- Returns import information about the provided path
--- @param path string
---     The path to check import details for
--- @return table
---     A table that contains either
---     {status = "unknown"}, if the path provided was not imported via the import method
---     or
---     {
---         status  = status,  -- String: This will be either success or failed
---         message = message, -- String: This will be either the error that was provided on import, or nil
---         errors  = errors,  -- Table: Any errors that the path threw during its import attempt
---         logs    = logs,    -- Table: Anything that was printed during the import (with approximate timestamps)
---     }
function M.get_status(module)
    local details = {status="unknown", imported=false, import_time=-1}
    if not M.import_statuses.info[module] then return details end
    if M.import_statuses.failures[module] then
        details.status = "failed"
    else
        details.status = "success"
        details.imported = true
    end

    details.message = M.import_statuses.info[module].import_message
    details.import_time = M.import_statuses.info[module].import_time
    details.errors = M.import_statuses.info[module].error_logs
    details.logs = M.import_statuses.info[module].print_logs

    return details
end

--- Will unload and reload the path (with import). Safe to call if path was not imported via the import function
--- @param path string
---     The path to import
--- @param success_callback function
---     Optional. Note, if not provided but one was used for the original import, we will simply call the
---     previous callback.
---     **To prevent this, pass "false" to success_callback, or provide a new callback**
function M.reload(path, success_callback)
    package.loaded[path] = nil
    M.import_statuses.failures[path] = nil
    M.import_statuses.successes[path] = nil
    local callback_message = ''
    if M.import_statuses.info[path] then
        local _success_callback = M.import_statuses.info[path].success_callback
        if success_callback == nil then
            success_callback = _success_callback
            callback_message = "with cached callback"
        end
    end
    if callback_message == '' and success_callback then
        callback_message = "with provided callback"
    end
    local message = "Reloading"
    if not M.import_statuses.info[path] then
        message = "Importing"
    end
    M.import_statuses.info[path] = nil
    print(message, path, callback_message)
    M.import(path, success_callback)
end

function M.init()
    if not vim.g._import_imported then
        M.config(require("import.opts"))
        -- if our global is not set, we will add Import to global space.
        _G.import = M.import
        vim.g._import_imported = true
        local _import = function(command_details)
            local modules = command_details.fargs
            for _, module in ipairs(modules) do
                M.import(module)
            end
        end

        local _reload = function(command_details)
            local modules = command_details.fargs
            if not modules then
                modules = M.get_imported_modules()
            end
            for _, module in ipairs(modules) do
                M.reload(module)
            end
        end

        local _status = function(command_details)
            local path = command_details.args
            local details = M.get_status(path)
            local message = path .. ': { imported=' .. tostring(details.imported) .. ', import_duration=' .. tostring(details.import_time / 1000000) .. ' milliseconds }'
            print(message)
        end

        local _complete = function()
            -- TODO: (Mike) Figure out why the sort here isn't being respected?
            return M.get_imported_modules()
        end
        vim.api.nvim_create_user_command("Import", _import, {
            nargs = '+',
        })
        vim.api.nvim_create_user_command("Reload", _reload, {
            nargs = '*',
            complete = _complete
        })
        vim.api.nvim_create_user_command("ImportStatus", _status, {
            nargs = 1,
            complete = _complete
        })
    end
end

function M.config(configuration)
    configuration = configuration or {}
    local _opts = vim.deepcopy(require("import.opts"))
    for key, value in pairs(configuration) do
        if key == 'output_split_type'
           and (value ~= 'horizontal' and value ~= 'vertical') then
            value = 'horizontal'
        end
        _opts[key] = value
    end
    M.user_opts = configuration
end

M.init()
return M
