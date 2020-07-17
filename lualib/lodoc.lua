local thread = require'thread'

local lodoc = {}

local source_files = setmetatable({}, {
  __index = function (_, file)
    local sections = { [''] = {} }
    local current_section = ''
    for line in io.lines(file) do
      local section_header = string.match(line, '^//### ?(.*)$')
      if section_header then
        current_section = section_header
        if not sections[current_section] then sections[current_section] = {} end
      else
        local s = sections[current_section]
        s[#s + 1] = line
      end
    end
    return sections
  end
})

function lodoc.lines(name)
  local line_iter = assert(io.lines(name))
  local lotest_block = false
  local n = 0
  return function ()
    local line = line_iter() n = n + 1
    if not line then return nil end
    local header, text = string.match(line, '^%-%-(#+) (.*)$')
    if text then lotest_block = true return { 'header', text, header_depth = #header, n = n, line = line } end
    local text = string.match(line, '^%-%-%. (.*)$')
    if text then lotest_block = true return { 'text', text, n = n, line = line } end
    local file, section = string.match(line, '^%-%-@ (.-):(.+)$')
    if file then lotest_block = true return { 'import', source_files[os.dirname(name)..'/'..file][section], fname = file, n = n, line = line } end
    if line == '--//' then return { 'ignore', '', n = n, line = line } end
    local input = string.match(line, '^%-%-$ (.*)$')
    if input then lotest_block = true return { 'input', input, n = n, line = line } end
    local output = string.match(line, '^%-%-  (.*)$')
    if lotest_block and output then return { 'output', output, n = n, line = line } end
    lotest_block = false
    return { 'other', line, n = n, line =  line }
  end
end

-- local function block_not_empty(block)
--   for _,line in ipairs(block) do
--     if #line[2] > 0 then return true end
--   end
-- end

local function grouped(lines)
  return coroutine.wrap(function ()
    local buf
    local prev_kind = nil
    for line in lines do
      if line[1] ~= prev_kind then
        if buf --[[and block_not_empty(buf)]] then coroutine.yield(buf) end
        buf = { kind = line[1], line } prev_kind = line[1]
      else
        buf[#buf+1] = line
      end
    end
    if #buf then coroutine.yield(buf) end
    return
  end)
end

local function block_joined_lines(block, sep)
  local lines = {}
  for _,line in ipairs(block) do
    lines[#lines + 1] = line[2]
  end
  return string.strip(table.concat(lines, sep))
end

function lodoc.html(fname, output)
  output = output or function (v) io.stdout:write(v) end
  output([[
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">

  <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/css/bootstrap.min.css"
        integrity="sha384-ggOyR0iXCbMQv3Xipma34MD+dH/1fQ784/j6cY/iJTQUOhcWr7x9JvoRxT2MZw1T" crossorigin="anonymous">
  <script src="https://code.jquery.com/jquery-3.3.1.slim.min.js"
        integrity="sha384-q8i/X+965DzO0rT7abK41JStQIAqVgRVzpbzo5smXKp4YfRvH+8abtTE1Pi6jizo" crossorigin="anonymous"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.14.7/umd/popper.min.js"
        integrity="sha384-UO2eT0CpHqdSJQ6hJty5KVphtPhzWj9WO1clHTMGa3JDZwrnQq4sF86dIHNDz0W1" crossorigin="anonymous"></script>
  <script src="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/js/bootstrap.min.js"
        integrity="sha384-JjSmVgyd0p3pXB1rRibZUAYoIIy6OrQ6VrjIEaFf/nJGzIxFDsf4x0xIM+B07jRM" crossorigin="anonymous"></script>

  <script src="https://cdnjs.cloudflare.com/ajax/libs/marked/1.1.1/marked.min.js"
        integrity="sha512-KCyhJjC9VsBYne93226gCA0Lb+VlrngllQqeCmX+HxBBHTC4HX2FYgEc6jT0oXYrLgvfglK49ktTTc0KVC1+gQ==" crossorigin="anonymous"></script>

  <link rel="stylesheet"
        href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/10.1.1/styles/default.min.css">
  <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/10.1.1/highlight.min.js"></script>

  <script>
    hljs.initHighlightingOnLoad();
    $('.collapse').collapse();
    $(function () {
      $('p').each(function () { this.outerHTML = marked(this.innerText) });
      $($('.source-button').get(0)).text('▶︎ Show imports').css('float', 'right');
    });
  </script>
  <style lang='text/css'>
    body {
      margin: 3em;
    }
    pre {
      margin: 0;
    }
    .container {
      position: relative;
    }
    pre.input code {
      background: #beb;
      margin: 0em 0 0 0;
      padding-bottom: .1em;
    }
    pre.output code {
      background: #dcf4f4;
      margin: 0 0 0em 0;
      padding-top: .1em;
    }
    h1, h2, h3, h4 {
      margin-top: 1em;
    }
    p {
      margin-top: 1rem;
      margin-bottom: .5rem;
    }
    p code {
      background: #eee;
      padding: .2em;
    }
    .source-button {
      color: #999;
    }
    .source-info {
      float: right;
      padding: .2em;
      background: #fff;
    }
  </style>
</head>
<body>
<div class="container">
]])
  for block in grouped(lodoc.lines(fname)) do
    D'»'(block.kind)
    if block.kind == 'header' then
      for _,header in ipairs(block) do
        output('<h'..header.header_depth..'>'..header[2]..'</h'..header.header_depth..'>\n')
      end
    elseif block.kind == 'text' then
      output('<p>'..block_joined_lines(block, '\n')..'</p>\n')
    elseif block.kind == 'input' then
      output('<pre class="input"><code class="language-lua">$ '..block_joined_lines(block, '\n$ ')..'\n</code></pre>\n')
    elseif block.kind == 'output' then
      output('<pre class="output"><code class="language-lua">'..block_joined_lines(block, '\n')..'\n</code></pre>\n')
    elseif block.kind == 'other' or block.kind == 'import' then
      local text, source, lang
      if block.kind == 'import' then
        text = string.strip(table.concat(block[1][2], '\n'))
        source = '<div class="source-info">'..string.match(block[1].fname, "[^/]+$")..':'..block[1].n..'</div>'
        lang = ''
      else
        text = block_joined_lines(block, '\n')
        source = ''
        lang = 'language-lua'
      end
      if #text > 0 then
        local id = 'source-block-'..block[1].n
        output([[<div><button class="source-button btn btn-sm btn-light" type="button" data-toggle="collapse" data-target="#]]..id..[[" aria-expanded="false" aria-controls="]]..id..[[">
    ▶︎ Show source
  </button></div>
<pre class="source collapse" id="]]..id..[["><code class="]]..lang..[[">]]..source..text..[[
</code></pre>]])
      end
    elseif block.kind == 'ignore' then
      break
    end
  end
  output[[
</div>
</body>
]]
end

if __MAIN__ then
  lodoc.html(arg[1])
end

return lodoc
