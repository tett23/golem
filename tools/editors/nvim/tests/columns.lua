-- I2: the columns of the diagnostics of golem lsp that Neovim receives do
-- not exceed the byte length of their lines (golem-lsp ADR 0003,
-- docs/adr/0231). The lines have Japanese and a 4-byte character, and the
-- error of the unclosed command is at the end of the file
return function(t)
  local f = assert(io.open(t.proj .. '/a.gm', 'w'))
  f:write('# 見出し\n\n😀[strong: 閉じない\n\n本文は😀と[ref-title nosuch]を見る。\n')
  f:close()
  local buf = t.edit('a.gm')
  t.start_lsp(nil)
  local ds = t.diagnostics(buf, 'diagnostics of a.gm', function(ds)
    return #ds > 0
  end)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local function len(l)
    return #(lines[l + 1] or '')
  end
  local within = true
  local detail = {}
  for _, d in ipairs(ds) do
    local end_lnum = d.end_lnum or d.lnum
    local end_col = d.end_col or d.col
    table.insert(detail, ('%s %d:%d-%d:%d'):format(d.code, d.lnum, d.col, end_lnum, end_col))
    if d.col > len(d.lnum) or end_col > len(end_lnum) then
      within = false
    end
  end
  t.expect_that('the columns are within their lines: ' .. table.concat(detail, ', '), within)
end
