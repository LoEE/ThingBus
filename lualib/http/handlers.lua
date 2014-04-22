local M = {}

function M.FileHandler (root, file, opts)
  return function (req, path)
    if file then return req:replyWithFile (root .. file, opts) end
    local parts = string.splitall (path, "/")
    local resolved = {}
    for _,part in ipairs(parts) do
      if part == "." or part == "" then
      elseif part == ".." then
        resolved[#resolved] = nil
      else
        resolved[#resolved+1] = part
      end
    end
    return req:replyWithFile (root .. table.concat(resolved, '/'), opts)
  end
end

return M
