-- The procedure of tools/editors/README.md for Neovim without
-- nvim-treesitter (docs/adr/0171, docs/adr/0231): test.sh has compiled the
-- parsers with the sh block of the README into GOLEM_NVIM_SITE and cut the
-- lua block of the README into GOLEM_NVIM_SITE/init.lua. text.gm and
-- fn/lib.emet of emet-samples, the files of docs/adr/0171, get the file
-- types golem and emet, and tree-sitter highlights them
return function(t)
  local site = assert(os.getenv('GOLEM_NVIM_SITE'), 'GOLEM_NVIM_SITE')
  -- the site directory of the README is on the runtimepath of Neovim,
  -- which --clean leaves out
  vim.opt.runtimepath:prepend(site)
  dofile(site .. '/init.lua')

  local samples = t.editors .. '/../../modules/golem-driver/test/fixtures/emet-samples/'
  -- each with the pattern of a line that starts with a capture: a heading,
  -- a comment
  local files = { { 'text.gm', 'golem', '^# ' }, { 'fn/lib.emet', 'emet', '^%-%- ' } }
  for i, f in ipairs(files) do
    local rel, ft, pattern = f[1], f[2], f[3]
    vim.fn.mkdir(vim.fs.dirname(t.proj .. '/' .. rel), 'p')
    t.check(vim.uv.fs_copyfile(samples .. rel, t.proj .. '/' .. rel), 'no ' .. samples .. rel)
    local buf = t.edit(rel)
    if i == 1 then
      t.expect('the file type of ' .. rel, vim.bo[buf].filetype, ft, 'text')
    else
      t.check(vim.bo[buf].filetype == ft, ('the file type of %s: %q, not %q'):format(rel, vim.bo[buf].filetype, ft))
    end
    t.wait_until('tree-sitter to highlight ' .. rel, function()
      return vim.treesitter.highlighter.active[buf] ~= nil
    end, 5000)
    local row
    for r, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if not row and l:find(pattern) then
        row = r - 1
      end
    end
    t.check(row, ('no line of %s matches %s'):format(rel, pattern))
    -- a headless Neovim draws nothing, and so the highlighter has not parsed
    vim.treesitter.get_parser(buf):parse(true)
    local captures = vim.treesitter.get_captures_at_pos(buf, row, 0)
    t.check(#captures > 0, ('no capture at the start of the line %d of %s'):format(row + 1, rel))
  end
end
