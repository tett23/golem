-- I5: the completion of style.toml and preflight.toml of the root, in
-- Neovim with vim.lsp.completion: the list shows the candidates, and the
-- line after the choice is the expected one, outside and inside quotes;
-- manifest.toml and a TOML file not at the root get no list (docs/adr ADR
-- 0169, docs/adr/0231). The list is read through ext_popupmenu, which a
-- terminal would draw
return function(t)
  local ns = vim.api.nvim_create_namespace('golem-nvim-test')
  local shown = {}
  vim.ui_attach(ns, { ext_popupmenu = true }, function(event, items)
    if event == 'popupmenu_show' then
      table.insert(shown, vim.tbl_map(function(item)
        return item[1]
      end, items))
    end
  end)
  vim.o.completeopt = 'menu,menuone,noselect'
  local done = {}
  vim.api.nvim_create_autocmd('LspRequest', {
    callback = function(ev)
      local req = ev.data.request
      if req.method == 'textDocument/completion' and req.type == 'complete' then
        done[ev.buf] = (done[ev.buf] or 0) + 1
      end
    end,
  })

  local client
  -- puts lines in rel, types A at its last line and asks for completion;
  -- the candidates of the list, or nil when the server answered and no
  -- list was shown
  local function complete(rel, text)
    local path = t.proj .. '/' .. rel
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    local buf = t.edit(rel)
    if not client then
      client = t.start_lsp(nil)
    else
      vim.lsp.buf_attach_client(buf, client.id)
    end
    vim.lsp.completion.enable(true, client.id, buf, { autotrigger = false })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n'))
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })
    local before_shown, before_done = #shown, done[buf] or 0
    t.feed('A<Cmd>lua vim.lsp.completion.get()<CR>')
    t.wait_until('the answer of the completion in ' .. rel, function()
      return (done[buf] or 0) > before_done
    end)
    -- the list comes after the answer
    t.sleep(200)
    return buf, shown[before_shown + 1]
  end

  -- chooses label from the list, leaves the insert mode and returns the line
  local function choose(buf, items, label)
    local idx
    for i, w in ipairs(items) do
      if w == label then
        idx = i
      end
    end
    t.check(idx, ('%s is not in the list %s'):format(label, vim.inspect(items)))
    t.feed(('<C-n>'):rep(idx) .. '<C-y><Esc>')
    t.wait_until('the end of the insert mode', function()
      return vim.api.nvim_get_mode().mode == 'n'
    end)
    local line = vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1]
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    return line
  end

  local cases = {
    { 'style.toml', '[page]\nbinding = ', '"right"', 'binding = "right"', 'binding = "right' },
    { 'style.toml', '[page]\nbinding = "', 'right', 'binding = "right' },
    { 'preflight.toml', 'based-on = ', '"print"', 'based-on = "print"' },
    { 'preflight.toml', 'based-on = "', 'print', 'based-on = "print' },
  }
  for _, c in ipairs(cases) do
    local rel, text, label, want, inverted = c[1], c[2], c[3], c[4], c[5]
    local buf, items = complete(rel, text)
    t.check(items and #items > 0, ('no list in %s after %q'):format(rel, text))
    local line = choose(buf, items, label)
    local what = ('the line of %s after %s is chosen'):format(rel, label)
    if inverted then
      t.expect(what, line, want, inverted)
    else
      t.check(line == want, ('%s: got %q, expected %q'):format(what, line, want))
    end
  end

  for _, rel in ipairs({ 'manifest.toml', 'sub/style.toml' }) do
    local _, items = complete(rel, '[')
    t.check(items == nil, ('a list in %s: %s'):format(rel, vim.inspect(items)))
    t.feed('<Esc>')
  end
end
