local M = {}

local uv = vim.uv

if bit == nil then
    bit = require("bit")
end

function M.get_plugin_path()
    local full_path = utils.get_path_lua_file()
    if not full_path then
        return nil
    end
    local subpath = "/lua/live-preview/utils.lua"
    return M.get_parent_path(full_path, subpath)
end

function M.uv_read_file(file_path)
    local fd = uv.fs_open(file_path, 'r', 438) -- 438 is decimal for 0666
    if not fd then
        print("Error opening file: " .. file_path)
        return nil
    end

    local stat = uv.fs_fstat(fd)
    if not stat then
        print("Error getting file info: " .. file_path)
        return nil
    end

    local data = uv.fs_read(fd, stat.size, 0)
    if not data then
        print("Error reading file: " .. file_path)
        return nil
    end

    uv.fs_close(fd)
    return data
end

M.get_path_lua_file = function()
    local info = debug.getinfo(2, "S")
    if not info then
        print("Cannot get info")
        return nil
    end
    local source = info.source
    if source:sub(1, 1) == "@" then
        return source:sub(2)
    end
end

M.get_parent_path = function(full_path, subpath)
    local escaped_subpath = subpath:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    local pattern = "(.*)" .. escaped_subpath
    local parent_path = full_path:match(pattern)
    return parent_path
end


M.term_cmd = function(cmd)
    local shell = "sh"
    if uv.os_uname().version:match("Windows") then
        shell = "pwsh"
    end

    local on_exit = function(result)
        return result
    end

    vim.system({ shell, '-c', cmd }, { text = true }, { on_exit })
end


function M.sha1(val)
    local function to_32_bits_str(number)
        return string.char(bit.band(bit.rshift(number, 24), 255)) ..
            string.char(bit.band(bit.rshift(number, 16), 255)) ..
            string.char(bit.band(bit.rshift(number, 8), 255)) ..
            string.char(bit.band(number, 255))
    end

    local function to_32_bits_number(str)
        return bit.lshift(string.byte(str, 1), 24) +
            bit.lshift(string.byte(str, 2), 16) +
            bit.lshift(string.byte(str, 3), 8) +
            string.byte(str, 4)
    end
    -- Mark message end with bit 1 and pad with bit 0, then add message length
    -- Append original message length in bits as a 64bit number
    -- Note: We don't need to bother with 64 bit lengths so we just add 4 to
    -- number of zeros used for padding and append a 32 bit length instead
    local padded_message = val ..
        string.char(128) ..
        string.rep(string.char(0), 64 - ((string.len(val) + 1 + 8) % 64) + 4) ..
        to_32_bits_str(string.len(val) * 8)

    -- Blindly implement method 1 (section 6.1) of the spec without
    -- understanding a single thing
    local H0 = 0x67452301
    local H1 = 0xEFCDAB89
    local H2 = 0x98BADCFE
    local H3 = 0x10325476
    local H4 = 0xC3D2E1F0

    -- For each block
    for M = 0, string.len(padded_message) - 1, 64 do
        local block = string.sub(padded_message, M + 1)
        local words = {}
        -- Initialize 16 first words
        local i = 0
        for W = 1, 64, 4 do
            words[i] = to_32_bits_number(string.sub(
                block,
                W
            ))
            i = i + 1
        end

        -- Initialize the rest
        for t = 16, 79, 1 do
            words[t] = bit.rol(
                bit.bxor(
                    words[t - 3],
                    words[t - 8],
                    words[t - 14],
                    words[t - 16]
                ),
                1
            )
        end

        local A = H0
        local B = H1
        local C = H2
        local D = H3
        local E = H4

        -- Compute the hash
        for t = 0, 79, 1 do
            local TEMP
            if t <= 19 then
                TEMP = bit.bor(
                        bit.band(B, C),
                        bit.band(
                            bit.bnot(B),
                            D
                        )
                    ) +
                    0x5A827999
            elseif t <= 39 then
                TEMP = bit.bxor(B, C, D) + 0x6ED9EBA1
            elseif t <= 59 then
                TEMP = bit.bor(
                        bit.bor(
                            bit.band(B, C),
                            bit.band(B, D)
                        ),
                        bit.band(C, D)
                    ) +
                    0x8F1BBCDC
            elseif t <= 79 then
                TEMP = bit.bxor(B, C, D) + 0xCA62C1D6
            end
            TEMP = (bit.rol(A, 5) + TEMP + E + words[t])
            E = D
            D = C
            C = bit.rol(B, 30)
            B = A
            A = TEMP
        end

        -- Force values to be on 32 bits
        H0 = (H0 + A) % 0x100000000
        H1 = (H1 + B) % 0x100000000
        H2 = (H2 + C) % 0x100000000
        H3 = (H3 + D) % 0x100000000
        H4 = (H4 + E) % 0x100000000
    end

    return to_32_bits_str(H0) ..
        to_32_bits_str(H1) ..
        to_32_bits_str(H2) ..
        to_32_bits_str(H3) ..
        to_32_bits_str(H4)
end

M.open_browser = function(path, browser)
    vim.validate({
        path = { path, 'string' },
    })
    local is_uri = path:match('%w+:')
    if not is_uri then
        path = vim.fn.expand(path)
    end

    local cmd
    if browser ~= 'default' then
        cmd = { browser, path }
    elseif vim.fn.has('mac') == 1 then
        cmd = { 'open', path }
    elseif vim.fn.has('win32') == 1 then
        if vim.fn.executable('rundll32') == 1 then
            cmd = { 'rundll32', 'url.dll,FileProtocolHandler', path }
        else
            return nil, 'vim.ui.open: rundll32 not found'
        end
    elseif vim.fn.executable('wslview') == 1 then
        cmd = { 'wslview', path }
    elseif vim.fn.executable('xdg-open') == 1 then
        cmd = { 'xdg-open', path }
    else
        return nil, 'vim.ui.open: no handler found (tried: wslview, xdg-open)'
    end

    local rv = vim.system(cmd, { text = true, detach = true })
    if rv.code ~= 0 then
        local msg = ('open_browser: command failed (%d): %s'):format(rv.code, vim.inspect(cmd))
        return rv, msg
    end

    return rv, nil
end


M.kill_port = function(port)
    local kill_command = string.format(
        "lsof -i:%d | grep -v 'neovim' | awk '{print $2}' | xargs kill -9",
        port
    )

    if vim.uv.os_uname().version:match("Windows") then
        kill_command = string.format(
            [[
                @echo off
                setlocal

                for /f "tokens=5" %%a in ('netstat -ano ^| findstr :%d') do (
                    for /f "tokens=2 delims=," %%b in ('tasklist /fi "PID eq %%a" /fo csv /nh') do (
                        if /i not "%%b"=="neovim.exe" (
                            echo Killing PID %%a (Process Name: %%b)
                            taskkill /PID %%a /F
                        )
                    )
                )

                endlocal
            ]],
            port
        )
    end
    os.execute(kill_command)
end


return M
