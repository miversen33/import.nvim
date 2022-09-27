--- Safely wraps the traditional require function that lua uses for importing modules
--- Use in place of "require".

local log_timestamp_format = '%Y-%m-%d %H:%M:%S'
local M = {}
local import_defaults = {
    hide_output = false,
    hide_errors = false
}

M.internal = {}

M.import_statuses = {
    failures = {},
    successes = {},
    info = {},
}

M.user_opts = {}
M._is_in_error_state = false
M._printed_error_state = false

--- Imports a single lua module
--- @param path string
---     The path to import
--- @param force boolean
---     Default: false
---     If true, forces the import through regardless of it there has been
---     a successful import already
--- @return table
---     Returns a table with the following structure
---     {
---         success,
---         duration,
---         output,
---         errors,
---         import_message,
---         module,
---         print_shim,
---         error_shim
---     }
---     Where each key is defined below
---     - success: Boolean
---         If the import was successful or not
---     - duration: Integer
---         The amount of time the import took
---     - output: table
---         A 1 dimensional table containing output emitted during import
---     - errors: table
---         A 1 dimensional table containing errors that were emitted during import
---     - import_message: string
---         Whatever message is emitted by neovim on completion of import. Usually this
---         will be an error that neovim itself encountered
---     - module: table
---        The module that was imported (or nil if the import failed)
---     - print_shim: function
---        A function that can be called to associate print output with the path
---     - error_shim: function
---       A function that can be called to associate errors with the path
function M.internal._import(path, force)
    local return_details = {
        success = false,
        duration = -1,
        output = {},
        errors = {},
        import_message = "",
        module = nil,
        print_shim = nil,
        error_shim = nil
    }
    local log_format = '%s - [%s] %s'
    return_details.print_shim = function(...)
        if not M.user_opts.import_enable_better_printing then
            table.insert(return_details.output, {...})
        else
            local print_safe_args = {}
            local _ = {...}
            for i=1, #_ do
                table.insert(print_safe_args, tostring(_[i]))
            end
            table.insert(return_details.output,
                string.format(
                    log_format,
                    path,
                    os.date(log_timestamp_format),
                    table.concat(print_safe_args)
                )
            )
        end
    end
    return_details.error_shim = function(...)
        if not M.user_opts.import_enable_better_printing then
            table.insert(return_details.errors, {...})
        else
            local print_safe_args = {}
            local _ = {...}
            for i=1, #_ do
                table.insert(print_safe_args, tostring(_[i]))
            end
            table.insert(return_details.errors,
                string.format(
                    log_format,
                    path,
                    os.date(log_timestamp_format),
                    table.concat(print_safe_args)
                )
            )
        end
    end

    -- Explicitly checking if force is true vs "truthy"
    if force == true then
        package.loaded[path] = nil
        M.import_statuses.info[path] = nil
    end
    if M.import_statuses.info[path] then
        return_details.success = true
        return_details.duration = M.import_statuses.info[path].import_time or 0
        return_details.module = package.loaded[path]
        return return_details
    end
    local _print = print
    local _error = error
    -- Overriding the global print and error functions
    _G.print = return_details.print_shim
    _G.error = return_details.error_shim
    local start_time = vim.loop.hrtime()
    local status, module_return = pcall(require, path)
    return_details.duration = vim.loop.hrtime() - start_time
    -- Putting the global print and error functions back
    _G.print = _print
    _G.error = _error
    if not status then
        return_details.import_message = module_return
        -- We don't _need_ to do this as it is false by default, but
        -- for clarity sake we will
        return_details.success = false
    else
        return_details.module = module_return
        return_details.success = true
    end
    return return_details
end

--- Use in place of "require"
--- @param imports string/table
---      A table of paths (or a single path as a string) to import. These paths 
---      should be exactly what you would pass to require
--- @param success_callback function
---     Optional: If provided, this function will be called on a successfull import of
---     the provided "path". This function will be provided the imported module(s) as
---     its single parameter.
---     Note: This is saved for calling later on reload
---     EG: success_callback(imported_module)
--- @param import_opts table
---     Optional: If provided, the following options are available to be used during
---     import.
---     hide_output = false,
---         -- When provided, this will hide anything that was printed, but still have it available
---         -- on the ImportStatus page
---     hide_errors = false,
---         -- When provided, this will hide anything that was printed to the errors, but still
---         -- be available on the ImportStatus page
--- @return nil
---
--- Examples
--- require("import.nvim") -- require the import package to get the ability to use its import functionality
--- import("netman") -- This module doesn't require setup so you dont need to specify it
--- import("lualine", function(lualine) lualine.setup{ "do your module setup here" } end)
--- import({"cmp", "cmp_nvim_lsp"}, function(modules)
---     -- Here since a table of imports was passed in, a table is passed back.
---     -- Notice that the table contains a set of key, value pairs where each key
---     -- is the name of the module that was provided in the `imports` param
---     -- and each value is the module that was imported.
---     -- NOTE: This is guaranteed to be safe to run as the callback is not called unless
---     -- _all_ imports were successful. Meaning `modules` will _always_ contain the listed key, value pairs
---     modules.cmp.setup()
---     modules.cmp_nvim_lsp.setup()
--- end)
function M.import(imports, success_callback, import_opts)
    -- TODO: (Mike) I am unsure if this is the best way to do handle an existing import or not?
    import_opts = import_opts or {}
    local compat_mode = false
    local compat_import = imports
    if type(imports) ~= "table" then
        imports = {imports}
        compat_mode = true
    end
    local imported_modules = {}
    local failed_import = true
    for _, path in ipairs(imports) do
        local return_details = M.internal._import(path, false)
        imported_modules[path] = return_details.module

        if not import_opts.hide_output then
            for _, log in ipairs(return_details.output) do
                print(log)
            end
        end
        if not import_opts.hide_errors then
            for _, log in ipairs(return_details.errors) do
                print(string.format("ERROR: %s", log))
            end
        end
        if not return_details.success then
            -- Import failed 😡
            M.import_statuses.failures[path] = 1
            M._is_in_error_state = true
        else
            -- Import was a success 😀
            failed_import = false
            M.import_statuses.successes[path] = 1
        end
        M.import_statuses.info[path] = {
            import_message=return_details.import_message,
            import_time=return_details.duration,
            print_logs=return_details.output,
            error_logs=return_details.errors,
            success_callback=success_callback,
            error_shim=return_details.error_shim,
            print_shim=return_details.print_shim,
            imported_with={}
        }
        if not compat_mode then
            for _, co_module in ipairs(imports) do
                if co_module ~= path then
                    table.insert(M.import_statuses.info[path].imported_with, co_module)
                end
            end
        end
    end
    if not failed_import and success_callback then
        local returner = imported_modules
        if compat_mode then
            -- To maintain backwards compatability, if there is only 1 module that was provided,
            -- pull out the module and return it in the callback
            returner = imported_modules[compat_import]
        end
        local callback_status, _ = pcall(success_callback, returner)
        if not callback_status then
            -- Callback failed 😡
            for name, module in pairs(imported_modules) do
                M.import_statuses.info[name].error_shim(string.format("Callback Error: %s", _))
                M.import_statuses.successes[name] = nil
                M.import_statuses.failures[name] = 1
            end

        end
    end
    if M._is_in_error_state and not M._printed_error_state then
        M._printed_error_state = true
        print("There was an error with your imports")
    end
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
--- @param module string
---     The path to check import details for
--- @return table
---     A table that contains either
---     {status = "unknown"}, if the path provided was not imported via the import method
---     or
---     {
---         status  = status,        -- String: This will be either success or failed
---         message = message,       -- String: This will be either the error that was provided on import, or nil
---         errors  = errors,        -- Table: Any errors that the path threw during its import attempt
---         logs    = logs,          -- Table: Anything that was printed during the import (with approximate timestamps)
---         co_modules = co_modules, -- Table: Any modules that were imported with this module
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
    local message = {}
    if M.import_statuses.info[module].import_message then
        for line, _ in M.import_statuses.info[module].import_message:gmatch('([^\r\n]*)') do
            table.insert(message,line)
        end
    end
    details.message = message
    details.import_time = M.import_statuses.info[module].import_time
    details.errors = M.import_statuses.info[module].error_logs
    details.logs = M.import_statuses.info[module].print_logs
    details.co_modules = M.import_statuses.info[module].imported_with
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
            local module = command_details.args
            if module:match('^%s*$') then
                -- Nothing/empty string was passed, display UI
                vim.api.nvim_command('echon ""') -- Be cool if print worked...
                require("import.ui").display(M.user_opts)
                return
            end
            local details = M.get_status(module)
            local message = string.format("%s: { imported=%s, import_duration=%s milliseconds, imported_with=%s}", module, details.imported, (details.import_time / 100000), table.concat(details.co_modules, ", "))
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
            nargs = '?',
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
    M.user_opts = _opts
end

M.init()
return M
