--
-- Pretty print / format class
--
local format = string.format
local sort = table.sort
local append = table.insert
local concat = table.concat
local floor = math.floor

local identifier = "^[_%a][_%w]*$"

-- trim whitespace from both ends of a string
local function trim(str)
    return (str:gsub("^%s*(.-)%s*$", "%1"))
end

-- encodes a string as you would write it in code,
-- escaping control and other special characters
local function escape_string(str)
  local function ctoh (c) return format("\\%03d", c:byte()) end

    local es_repl = { ["\n"] = "\\n", ["\r"] = "\\r",
        ["\\"] = "\\\\", ['"'] = '\\"' }
    str = str:gsub('(["\r\n\\])', es_repl)
    str = str:gsub('([\v\f\t])', ctoh)
    str = str:gsub("([^%w%p%s])", ctoh)
    return format('"%s"', str)
end

-- function varsub(str, repl)
-- replaces variables in strings like "%20s{foo} %s{bar}" using the table repl
-- to look up replacements. use string:format patterns followed by {variable}
-- and pass the variables in a table like { foo="FOO", bar="BAR" }
-- variable names need to match Lua identifiers ([_%a][_%w]-)
-- missing variables or errors in formatting will result in empty strings
-- being inserted for the corresponding placeholder pattern
local function varsub(str, repl)
    return str:gsub("(%%.-){([_%a][_%w]-)}", function(f,k)
        local r, ok = repl[k]
        ok, r = pcall(format, f, r)
        return ok and r or ""
    end)
end

local Pretty = {}

Pretty.defaults = {
    items = 100,                  -- max number of items to list in one table
    depth = 7,                    -- max recursion depth when printing tables
    len = math.huge,              -- max line length hint
    delim1 = ", ",                -- item delimiter (single line / compact)
    delim2 = ", ",                -- item delimiter (multiline)
    indent1 = "    ",             -- string repeated each indent level
    indent2 = "    ",             -- string used to indent final level
    indent3 = "    ",             -- string used to indent final level continuation
    empty = "{ }",                -- string used for empty table
    bl = "{ ",                    -- table braces, single line mode
    br = " }",
    bl_m = "{\n",                 -- table braces, multiline mode, substitution available:
    br_m = "\n%s{i}}",            -- %s{i}, %s{i1}, %s{i2}, %s{i3} are calulated indents
    eol = "\n",                   -- end of line (multiline)
    sp = " ",                     -- used other places where spacing might be desired but optional
    eq = " = ",                   -- table equals string value (printed as key..eq..value)
    key = false,                  -- format of key in field (set to pattern to enable)
    value = false,                -- format of value in field (set to pattern to enable)
    field = "%s",                 -- format of field (which is either "k=v" or "v", with delimiter)
    tstr = true,                  -- use to tostring(table) if table has meta __tostring
    table_info = false,           -- show the table info (usually a hex address)
    function_info = false,        -- show the function info (similar to table_info)
    metatables = false,           -- show metatables when printing tables
    multiline = true,             -- set to false to disable multiline output
    compact = true,               -- will compact leaf tables in multiline mode
}

Pretty.__call = function(self, ...)
    self:print(...)
end

function Pretty:new(params)
    local obj = {}
    params = params or {}
    setmetatable(obj, self)
    self.__index = self
    obj:init(params)
    return obj
end

function Pretty:init(params)
    for k, v in pairs(self.defaults) do
        self[k] = v
    end
    for k, v in pairs(params) do
        self[k] = v
    end
    self.print_handlers = self.print_handlers or {}
    self:reset_seen()
end


function Pretty:reset_seen()
    self.seen = {}
    setmetatable(self.seen, { __do_not_enter = "<< ! >>" })
end

function Pretty:table2str(tbl, path, depth, multiline)
    -- don't print tables we've seen before
    for p, t in pairs(self.seen) do
        if tbl == t then
            local tinfo = self.table_info and tostring(tbl) or p
            return format("<< %s >>", tinfo)
        end
    end
    -- max_depth
    self.seen[path] = tbl
    if depth >= self.depth then
        return ">>>"
    end
    return self:table_children2str(tbl, path, depth, multiline)
end

-- this sort function compares table keys to allow a sort by key
-- the order is: numeric keys, string keys, other keys(converted to string)
function Pretty.key_cmp(a, b)
    local at = type(a)
    local bt = type(b)
    if at == "number" then
        if bt == "number" then
            return a < b
        else
            return true
        end
    elseif at == "string" then
        if bt == "string" then
            return a < b
        elseif bt == "number" then
            return false
        else
            return true
        end
    else
        if bt == "string" or bt == "number" then
            return false
        else
            return tostring(a) < tostring(b)
        end
    end
end

-- returns an iterator to sort by table keys using func
-- as the comparison func. defaults to Pretty.key_cmp
function Pretty.pairs_by_keys(tbl, func)
    func = func or Pretty.key_cmp
    local a = {}
    for n in pairs(tbl) do a[#a + 1] = n end
    sort(a, func)
    local i = 0
    return function ()  -- iterator function
        i = i + 1
        return a[i], tbl[a[i]]
    end
end

function Pretty:table_children2str(tbl, path, depth, multiline)
    local ind1, ind2, ind3  = "", "", ""
    local delim1, delim2 = self.delim1, self.delim2
    local sp, eol, eq = self.sp, self.eol, self.eq
    local bl, br = self.bl, self.br
    local bl_m, br_m = self.bl_m, self.br_m
    local tinfo = self.table_info and tostring(tbl)..sp or ""
    local key_fmt, val_fmt, field = self.key, self.val, self.field
    local compactable, cnt, c = 0, 0, {}
    -- multiline setup
    if multiline then
        ind1 = self.indent1:rep(depth)
        ind2 = ind1 .. self.indent2
        ind3 = ind1 .. self.indent3
        local irepl = { i=ind1, i1=ind1, i2=ind2, i3=ind3 }
        bl_m, br_m = varsub(bl_m, irepl), varsub(br_m, irepl)
    end
    -- metatable
    if self.metatables then
        local mt = getmetatable(tbl)
        if mt then
            append(c, "<metatable>".. self.eq .. self:val2str(mt,
                path .. (path == "" and "" or ".") .. "<metatable>", depth + 1, multiline))
        end
    end

    -- process child nodes, sorted
    local last = nil
    for k, v in Pretty.pairs_by_keys(tbl, self.sort_function) do
        -- item limit
        if self.items and cnt >= self.items then
            append(c, "...")
            compactable = compactable + 1
            break
        end
        -- determine how to display the key. array part of table will show no keys
        local print_index = true
        local print_brackets = true
        if type(k) == "number" then
            if (last and k > 1 and k == last + 1) or (not last and k == 1) then
                print_index = false
                last = k
            else
                last = false
            end
        else
            last = nil
        end
        local key = tostring(k)
        if type(k) == "string" then
            if k:match(identifier) then
                print_brackets = false
            else
                key = escape_string(key)
            end
        end
        if print_brackets then
            key = '[' .. key .. ']'
        end
        -- format val
        local val = self:val2str(v,
            path .. (path == "" and "" or ".") .. key, depth + 1, multiline)
        if not val:match("[\r\n]") then
            compactable = compactable + 1
        end
        if val_fmt then
            val = val_fmt:format(val)
        end
        -- put the pieces together
        local out = ""
        if key_fmt then
            key = key_fmt:format(key)
        end
        if print_index then
            out = key .. eq .. val
        else
            out = val
        end
        append(c, out)
        cnt = cnt + 1
    end

    -- compact
    if multiline and self.compact and #c > 0 and compactable == #c then
        local lines = {}
        local line = ""
        for i, v in ipairs(c) do
            local f = field:format(v .. (i == cnt and "" or delim1))
            if line == "" then
                line = ind2 .. f
            elseif #line + #f <= self.len then
                line = line .. f
            else
                append(lines, line)
                line = ind3 .. f
            end
        end
        append(lines, line)
        return tinfo .. bl_m .. concat(lines, eol) .. br_m
    elseif #c == 0 then -- empty
        return tinfo .. self.empty
    elseif multiline then -- multiline
        local c2 = {}
        for i, v in ipairs(c) do
            append(c2, ind2 .. field:format(v .. (i == cnt and "" or delim2)))
        end
        return tinfo .. bl_m .. concat(c2, eol) .. br_m
    else -- single line
        local c2 = {}
        for i, v in ipairs(c) do
            append(c2, field:format(v .. (i == cnt and "" or delim1)))
        end
        return tinfo .. bl .. concat(c2) .. br
    end
end

function Pretty:val2str(val, path, depth, multiline)
    local tp = type(val)
    if self.print_handlers[tp] then
        local s = self.print_handlers[tp](val)
        return s or '?'
    end
    if tp == 'function' then
        return self.function_info and tostring(val) or "function"
    elseif tp == 'table' then
        local mt = getmetatable(val)
        if mt and mt.__do_not_enter then
            return mt.__do_not_enter
        elseif self.tstr and mt and mt.__tostring then
            return tostring(val)
        else
            return self:table2str(val, path, depth, multiline)
        end
    elseif tp == 'string' then
        return escape_string(val)
    elseif tp == 'number' then
        -- we try only to apply floating-point precision for numbers deemed to be floating-point,
        -- unless the 3rd arg to precision() is true.
        if self.num_prec and (self.num_all or floor(val) ~= val) then
            return self.num_prec:format(val)
        else
            return tostring(val)
        end
    else
        return tostring(val)
    end
end

function Pretty:format(...)
    local out, v = "", nil
    -- first try single line output
    self:reset_seen()
    for i = 1, select("#", ...) do
        v = select(i, ...)
        out = format("%s%s ", out, self:val2str(v, "", 0, false))
    end
    -- if it is too long, use multiline mode, if enabled
    if self.multiline and #out > self.len then
        out = ""
        self:reset_seen()
        for i = 1, select("#", ...) do
            v = select(i, ...)
            out = format("%s%s\n", out, self:val2str(v, "", 0, true))
        end
    end
    self:reset_seen()
    return trim(out)
end

function Pretty:print(...)
    local output = self:format(...)
    if self.output_handler then
        self.output_handler(output)
    else
        if output and output ~= "" then
            print(output)
        end
    end
end

return Pretty
