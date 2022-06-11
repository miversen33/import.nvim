local M = {}

M.lines = {}
M.is_displayed = false
M.buf_handle = nil
M.view_buf_handle = nil
M._user_opts = nil

function M._init(_opts)
    M._user_opts = _opts
end

function M.display(opts)
    -- Short circuit if we are already displayed
    if M.is_displayed then return end
    local importer = require("import")

    M._init(opts)
    local cur_ui = vim.api.nvim_list_uis()[1]
    if not M.buf_handle or not vim.api.nvim_buf_is_loaded(M.buf_handle) then
        M.buf_handle = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(M.buf_handle, "ImportManager")
    end
    if not M.view_buf_handle or not vim.api.nvim_buf_is_loaded(M.view_buf_handle) then
        M.view_buf_handle = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(M.view_buf_handle, "ImportManager_Viewer")
    end

    local float_height = math.floor(cur_ui.height * .9)
    local float_width = math.floor(cur_ui.width * .9)
    local view_height = nil
    local view_width = nil
    local float_col = nil
    local float_row = nil
    local view_col = nil
    local view_row = nil

    if M._user_opts.output_split_type == 'horizontal' then
        view_height = math.floor(float_height * .3)
        view_width = float_width
        float_height = float_height - view_height
        float_col = (cur_ui.width / 2) - (float_width / 2)
        float_row = (cur_ui.height / 2) - (float_height / 2) - (view_height / 2)
        view_col = (cur_ui.width / 2) - (view_width / 2)
        view_row = (cur_ui.height / 2) - (view_height / 2) + (float_height / 2)
    else
        view_height = float_height
        view_width = math.floor(float_width * .3)
        float_width = float_width - view_width
        float_col = (cur_ui.width / 2) - (float_width / 2) - (view_width / 2)
        float_row = (cur_ui.height / 2) - (float_height / 2)
        view_col = (cur_ui.width / 2) - (view_width / 2) + (float_width / 2)
        view_row = (cur_ui.height / 2) - (view_height / 2)
    end


    local float_opts = {
        relative = 'editor',
        width = float_width,
        height = float_height,
        col = float_col,
        row = float_row,
        style = 'minimal'
    }

    local view_opts = {
        relative = 'editor',
        width = view_width,
        height = view_height,
        col = view_col,
        row=view_row,
        style='minimal'
    }

    local failures = {}
    local successes = {}
    local import_details = {}
    for _, module in ipairs(importer.get_imported_modules()) do
        local details = importer.get_status(module)
        import_details[module] = details
        if details.imported then table.insert(successes, module) else table.insert(failures, module) end
    end
    local title = "Import Manager"
    local title_padding = (view_width / 2) - (title:len() / 2)
    title = string.rep(' ', title_padding) .. title
    local lines = {title}
    M.lines = {-1}
    for _, _failed_import in ipairs(failures) do
        table.insert(lines, M._format_module(_failed_import, import_details[_failed_import]))
        table.insert(M.lines, _failed_import)
    end
    table.insert(lines, "")
    table.insert(M.lines, -1)
    for _, _success_import in ipairs(successes) do
        table.insert(lines, M._format_module(_success_import, import_details[_success_import]))
        table.insert(M.lines, _success_import)
    end

    vim.api.nvim_buf_set_option(M.buf_handle, 'modifiable', true)
    vim.api.nvim_buf_set_lines(M.buf_handle, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(M.buf_handle, 'modifiable', false)
    vim.api.nvim_buf_set_option(M.buf_handle, 'filetype', "ImportManager")
    vim.api.nvim_buf_set_option(M.buf_handle, 'modified', false)
    vim.api.nvim_buf_set_option(M.view_buf_handle, 'modifiable', false)
    vim.api.nvim_buf_set_option(M.view_buf_handle, 'filetype', "ImportManager")
    vim.api.nvim_buf_set_option(M.view_buf_handle, 'modified', false)
    vim.api.nvim_buf_set_keymap(M.buf_handle, 'n', M._user_opts.keypress_select, ':lua require("import.ui")._selected_module(vim.fn.line("."))<CR>', {noremap=true, silent=true})
    vim.api.nvim_buf_set_keymap(M.buf_handle, 'n', M._user_opts.keypress_close,  ':lua require("import.ui").close()<CR>', {noremap=true, silent=true})
    vim.api.nvim_create_autocmd('BufDelete', {
        buffer = M.buf_handle,
        desc = "Clear out Cache for import UI",
        callback = M.close,
        once = true
    })
    vim.api.nvim_create_autocmd('WinClosed', {
        buffer = M.buf_handle,
        desc = "Clear out cache for import UI",
        callback = M.close,
        once = true
    })
    vim.api.nvim_create_autocmd('CursorMoved', {
        buffer = M.buf_handle,
        desc = "Loading Details into View Buffer",
        callback = M._load_info,
    })
    vim.api.nvim_open_win(M.view_buf_handle, 1, view_opts)
    vim.api.nvim_open_win(M.buf_handle, 1, float_opts)
end

function M._format_module(module, details)
    local icon = ""
    if not details then details = require("import").get_status(module) end
    if details.imported then
        icon = M._user_opts.import_success_icon
    else
        icon = M._user_opts.import_failed_icon
    end
    return " " .. icon .. " " .. tostring(module)
end

function M._update_main_buffer_line(lineno, new_text)
    vim.api.nvim_buf_set_option(M.buf_handle, 'modifiable', true)
    vim.api.nvim_buf_set_lines(M.buf_handle, lineno - 1, lineno, false, {new_text})
    vim.api.nvim_buf_set_option(M.buf_handle, 'modifiable', false)
end

function M._selected_module(line)
    module = M._get_module(line)
    if not module then return end
    M._update_main_buffer_line(line, "...")
    require("import").reload(module)
    M._update_main_buffer_line(line, M._format_module(module))
end

function M._get_module(line)
    line = M.lines[line]
    if not line or line == -1 then
        return
    end
    return line
end

function M._load_info()
    local module = M._get_module(vim.api.nvim_win_get_cursor(0)[1])
    if not module then
        vim.api.nvim_buf_set_option(M.view_buf_handle, 'modifiable', true)
        vim.api.nvim_buf_set_lines(M.view_buf_handle, 0, -1, false, {})
        vim.api.nvim_buf_set_option(M.view_buf_handle, 'modifiable', true)
        return
    end
    local details = require("import").get_status(module)

    local lines = {}
    table.insert(lines, module)
    table.insert(lines, "    Imported: " .. details.status)
    table.insert(lines, "    Import Time: " .. details.import_time / 10000 .. " milliseconds")
    table.insert(lines, "")
    table.insert(lines, "    Errors: " .. table.concat(details.errors, ' '))
    table.insert(lines, "    Logs: ")
    for _, log in ipairs(details.logs) do
        table.insert(lines, log)
    end
    vim.api.nvim_buf_set_option(M.view_buf_handle, 'modifiable', true)
    vim.api.nvim_buf_set_lines(M.view_buf_handle, 0, -1, false, {})
    vim.api.nvim_buf_set_lines(M.view_buf_handle, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(M.view_buf_handle, 'modifiable', false)
    vim.api.nvim_buf_set_option(M.view_buf_handle, 'modified', false)
end

function M.close()
    M.is_displayed = false
    M.modules = {}
    if M.buf_handle and vim.api.nvim_buf_is_loaded(M.buf_handle) then
        vim.api.nvim_buf_delete(M.buf_handle, {force=true})
    end
    if M.view_buf_handle and vim.api.nvim_buf_is_loaded(M.view_buf_handle) then
        vim.api.nvim_buf_delete(M.view_buf_handle, {force=true})
    end
    M.buf_handle = nil
    M.view_buf_handle = nil
end

return M
