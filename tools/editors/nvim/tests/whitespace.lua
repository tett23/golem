-- I4: the spaces in a command and in an expression are semantic tokens of
-- the type operator (golem-lsp ADR 0008), and the highlight groups at
-- them have no background and no underline: with the default color scheme
-- (test.sh), or with the configuration of whoever runs test.sh --theme
-- (docs/adr/0231)
return function(t)
  local buf = t.edit('a.gm')
  t.start_lsp(nil)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- 0-based rows and byte columns of the spaces
  local function space_after(pattern)
    for i, l in ipairs(lines) do
      local s, e = l:find(pattern, 1, true)
      if s then
        return i - 1, e
      end
    end
    t.fail('no ' .. pattern .. ' in a.gm')
  end
  local spaces = {}
  local r, c = space_after('[ref-number')
  table.insert(spaces, { 'the space of the command [ref-number second]', r, c })
  r, c = space_after('[= 1')
  table.insert(spaces, { 'the space of the expression [= 1 + 2]', r, c })

  for i, s in ipairs(spaces) do
    local what, row, col = s[1], s[2], s[3]
    local toks = t.wait_until('the semantic tokens at ' .. what, function()
      -- get_at_pos also gives a token that ends at col; those that cover
      -- the byte at col are kept
      local ts = vim.tbl_filter(function(tok)
        return tok.line == row and tok.start_col <= col and col < tok.end_col
      end, vim.lsp.semantic_tokens.get_at_pos(buf, row, col) or {})
      return #ts > 0 and ts
    end)
    local types = vim.tbl_map(function(tok)
      return tok.type
    end, toks)
    if i == 1 then
      t.expect('the types of the semantic tokens at ' .. what, types, { 'operator' }, { 'string' })
    else
      t.check(vim.deep_equal(types, { 'operator' }), 'the types of the semantic tokens at ' .. what .. ': ' .. vim.inspect(types))
    end
    -- the groups Neovim highlights the position with, resolved through
    -- their links
    local groups = {}
    for _, kind in ipairs({ 'semantic_tokens', 'treesitter', 'syntax', 'extmarks' }) do
      for _, item in ipairs(vim.inspect_pos(buf, row, col)[kind] or {}) do
        local g = item.hl_group or (item.opts and item.opts.hl_group)
        if g then
          table.insert(groups, g)
        end
      end
    end
    t.check(#groups > 0, 'no highlight group at ' .. what)
    for _, g in ipairs(groups) do
      local hl = vim.api.nvim_get_hl(0, { name = g, link = false })
      for _, attr in ipairs({ 'bg', 'underline', 'undercurl' }) do
        t.check(not hl[attr], ('%s: the group %s has %s: %s'):format(what, g, attr, vim.inspect(hl)))
      end
    end
  end
end
