-- I3: a notice of golem lsp is an INFO diagnostic in Neovim, is in the
-- quickfix list, and is gone after its code is written in silence-notices
-- and the file is saved (golem-syntax ADR 0002, docs/adr/0231)
return function(t)
  local f = assert(io.open(t.proj .. '/a.gm', 'w'))
  f:write('[tcy: 10]\n\n@number 1\n# A\n')
  f:close()
  local buf = t.edit('a.gm')
  -- the watched files, which golem lsp registers for manifest.toml: Neovim
  -- offers them on macOS and Windows only, and so they are asked for here
  -- (see tools/editors/README.md)
  local caps = vim.lsp.protocol.make_client_capabilities()
  caps.workspace.didChangeWatchedFiles.dynamicRegistration = true
  t.start_lsp(caps)
  -- G02063, the notice of [tcy: 10]
  local n = t.wait_until('the notice G02063 of a.gm', function()
    for _, d in ipairs(vim.diagnostic.get(buf)) do
      if d.code == 'G02063' then
        return d
      end
    end
  end)
  t.expect('the severity of ' .. tostring(n.code), n.severity, vim.diagnostic.severity.INFO, vim.diagnostic.severity.WARN)

  vim.diagnostic.setqflist({ open = false })
  local found = false
  for _, e in ipairs(vim.fn.getqflist()) do
    if e.bufnr == buf and e.lnum == n.lnum + 1 and e.type == 'I' and e.text:find(n.message, 1, true) then
      found = true
    end
  end
  t.check(found, 'the notice ' .. tostring(n.code) .. ' is not in the quickfix list: ' .. vim.inspect(vim.fn.getqflist()))

  -- silence-notices of the [diagnostics] of the manifest, written and saved
  local mbuf = t.edit('manifest.toml')
  vim.api.nvim_buf_set_lines(mbuf, -1, -1, false, { '', '[diagnostics]', ('silence-notices = ["%s"]'):format(n.code) })
  vim.cmd("silent write")
  t.diagnostics(buf, 'the notice ' .. tostring(n.code) .. ' to go', function(now)
    for _, d in ipairs(now) do
      if d.code == n.code then
        return false
      end
    end
    return true
  end)
end
