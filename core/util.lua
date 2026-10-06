local M = {}

function M.logger(tag)
	return function(fmt, ...)
		io.stderr:write("[" .. tag .. "] " .. string.format(fmt, ...) .. "\n")
	end
end

function M.file_mtime(path)
	local p = io.popen(string.format("stat -c %%Y '%s' 2>/dev/null", path))
	if not p then
		return nil
	end
	local out = p:read("*l")
	p:close()
	return tonumber(out)
end

return M
