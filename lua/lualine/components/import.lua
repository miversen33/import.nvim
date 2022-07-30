local M = require("lualine.component"):extend()
local import = require("import")

function M:update_status()
      local failed_imports = import.get_failure_count()
      local status = ''
      if failed_imports > 0 then
            status = failed_imports .. " " .. import.user_opts.import_failed_icon
      end
      return status
end

function M:init(options)
      if not options.on_click then
            options.on_click = function()
                  if import.get_failure_count() > 0 then
                        vim.cmd(':ImportStatus')
                  end
            end
      end
      M.super.init(self, options)
end

return M
