# import.nvim
A safe require replacement with niceties

## Table of Contents
- [Intro/TLDR](#introduction)
    - [Getting Started](#getting-started)
    - [Details](#details)
- [UI](#ui)
    - [Configuration](#ui-configuration) 
- [Vim Commands](#vim-commands)
    - [:Import](#import)
    - [:Reload](#reload)
    - [:ImportStatus](#importstatus)
- [Import API](#import-api)
    - [import.import](#importimport)
    - [import.reload](#importreload)
    - [import.get_status](#importgetstatus)
    - [import.get_success_count](#importgetsuccesscount)
    - [import.get_failure_count](#importgetfailurecount)
    - [import.config](#importconfig)

### Introduction
import.nvim is a lua plugin that allows for safely importing packages [similar 
to pcall](https://www.lua.org/pil/8.4.html) that has some added niceties for 
hot reloading modules from Vim `Command Mode` or Lua. This enables developers to 
expirement with new configurations with plugins with the ability to hot load
the changes without restarting neovim, hot reloading a plugin they are 
working on, etc.

#### Getting Started:
1) Include "import" before doing any requires    
    ```lua
    require('import')
    ```
2) Use `import` im place of [`require`](https://www.lua.org/pil/8.1.html)
    ```lua
    import('netman')
    ```
    Note: you can provide a callback which will be called on successful import
    ```lua
    import('netman', function(netman)
        netman.setup({ "do module setup" })
    end)
    ```
3) Profit!

#### Details
Import wraps the inbuilt lua [`pcall`](https://www.lua.org/pil/8.4.html) function to ensure safety with module 
importing, while also providing a mechanic to reload modules. Additionally,
Import captures (and timestamps) any errors or prints that are outputted 
during a module's import and stores them for later viewing by the developer. 
Lastly, import stores the amount of time it took for a module to complete its 
import process, which can be used later for profiling purposes (or whatever 
your heart desires). This is accomplished via the addition of a global function
[`import`](#import) which is done on the initial module import of [`import`](#getting-started).

Note: Import checks the `vim.g._import_imported` variable to ensure that there
we only run our init once.

### UI
If you use the [`:ImportStatus`](#importstatus) command with no arguments, a floating window is presented with 
the various packages that import imported for you. Additionally, there is a second pane that will display information
about the import include
- Import Duration
- If the package was imported successfully
- What it printed during its import
- Any errors it threw

#### UI Configuration
Currently the UI can be configured by calling the [`import.config`](#importconfig) function after loading import.
All options found in [the options file](https://github.com/miversen33/import.nvim/blob/main/lua/import/opts.lua) can be overriden
though there are some sanity checks to ensure that the options are valid.
The available options (and their defaults) are

- keypress_select             = "<Enter>",
- keypress_close              = '<Esc>',
- keypress_scroll_output_down = '<C-Down>',
- keypress_scroll_output_up   = '<C-Up>',
- output_split_type           = 'horizontal', -- Can also be vertical, if I dont know what you passed I will assume horizontal
- import_failed_icon          = "⛔",
- import_success_icon         = "✅",
- import_enable_better_printing = false

Note: `output_split_type` **MUST** be either `'horizontal'` or `'vertical'`. Failure to provide a valid option will result in the default
being used.
    
### Vim Commands

#### :Import
Takes `1-n` arguments and calls [import.import](#importimport) for each argument.

Usage:
```vim
:Import telescope netman lualine
```
See Also: [import.import](#importimport)

#### :Reload
Takes `0-n` arguments and calls import.reload| for each argument.
Note, if 0 arguments are provided, performs a reload on _all_ imported modules.

Usage:
```vim
:Reload netman lualine
```
OR
```vim
:Reload
```
See Also: [import.reload](#importreload)

#### :ImportStatus
Takes 0 or 1 argument and calls [import.get_status](#importgetstatus).  
If no argument is provided, reaches out and starts the Import Manager UI.
Otherwise prints the results to the print area.
Prints the following string:  
`module: { imported=true/false, import_duration=time_took_for_import }`

Usage:
```vim
:ImportStatus telescope 
```
OR
```vim
:ImportStatus
```
See Also: [import.get_status](#import)

### Import API
The api behind import is pretty simplistic but provides 2 features
- The ability to manage importing/reloading of modules
- The ability to query import details after import is complete

This is achieved through the following functions

#### import.import
Neovim (lua) exposed function that can be used to import a module and 
optionally specify its callback on success. Takes the following params
- path (string)
- success_callback (function, Optional)
If the import is successful, success_callback is called (if provided) and is 
given the imported module as a parameter to operate on. This way there is very
little retrofitting a user has to do to adopt `import` into their plugin
configuration.

Usage:
```lua
require("myplugin").setup({dostuff="yes"})
```
This can be modified slightly to the following to ensure safe importing (among
other things described in [Introduction](#introduction))
```lua
import("myplugin", function(myplugin) myplugin.setup({dostuff="yes'}) end)
```
See Also: [:Import](#import)

#### import.reload
Neovim (lua) exposed function that can be used to reload a module and 
optionally specify its callback on success. Takes the following params
- path (string)
- success_callback (function, Optional)

Note: If success_callback is not provided and one was used on [import.import](#importimport), we will simply use that one again on reload. To prevent this behavior, either provide a new callback to take the place of the cached one, or provide the
boolean `false` (which will clear out the cached callback and not store a new
one). This is useful for a variety of reasons, from plugin development to 
configuration experimentation.

Usage:
```lua
require("import").reload("myplugin")
-- Note, as we provided a callback in the above example, that same callback
-- will be called again on reload
```
OR
```lua
require("import").reload("myplugin", function(myplugin) myplugin.setup({
dostuff="no"}) end)
-- Note, this will override the previously stored success callback and
-- any subsequent reloads will call this callback instead
```
OR
```lua
require("import").reload("myplugin", false)
-- Note, this will _remove_ any success callback associated with this module
```

See Also: [:Reload](#reload)

#### import.get_status
Neovim (lua) exposed function that allows a user to query the status of a
particular path's import status. 
Takes the following params
- path (string)

Returns the following table
```lua
{ status = "unknown" } -- If path was not imported with |import.import|
```
OR
```lua
{
    status  = status,  -- String: This will be either success or failed
    message = message, -- String: This will be either the error that 
                       --     was provided on import, or nil
    errors  = errors,  -- Table: Any errors that the path threw during 
                       --     its import attempt
    logs    = logs,    -- Table: Anything that was printed during the 
                       --     import (with approximate timestamps)
}
```

Usage:
```lua
require("import").get_status("myplugin")
```
See Also: [:ImportStatus](#importstatus)

#### import.config
Neovim (lua) exposed function that expects a table that contains key, value pairs where the key matches 
what is found in import.opts.
Usage:
```lua
require("import").config({
    -- Your customizations here
})
```
See Also: [UI Configuration](#ui-configuration)
    
#### import.get_success_count
Neovim (lua) exposed function that returns the number (integer) of successfully
imported modules

Usage: 
```lua
require("import").get_success_count()
```

#### import.get_failure_count
Neovim (lua) exposed functino that returns the number (integer) of modules that
failed to import

Usage:
```lua
require("import").get_failure_count()
```
