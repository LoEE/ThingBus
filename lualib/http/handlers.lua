local M = {}

function M.FileHandler (root, file)
  return function (req, path)
    if file then return req:replyWithFile (root .. file) end
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
    return req:replyWithFile (root .. table.concat(resolved, '/'))
  end
end

return M
