-- Loads the patterns and exceptions of data/hyphenation/ into new
-- languages of LuaTeX, \lang<tag> holding the number of each (the tag
-- without its hyphen), for showhyphens.tex.
local function readall(p)
  local f = io.open(p, 'rb')
  if not f then return nil end
  local s = f:read('*a')
  f:close()
  return s
end
-- every letter of the patterns is a letter of a word: its lccode is itself
local function letters(s)
  for _, c in utf8.codes(s) do
    local ch = utf8.char(c)
    if not ch:match('^[0-9.%s-]$') then tex.setlccode(c, c) end
  end
end
for _, tag in ipairs({'en-us', 'en-gb', 'fr', 'de-1996', 'es', 'it', 'pt', 'nl'}) do
  local l = lang.new()
  local pat = readall('hyph-' .. tag .. '.pat.txt')
  letters(pat)
  lang.patterns(l, pat)
  local hyp = readall('hyph-' .. tag .. '.hyp.txt')
  if hyp then lang.hyphenation(l, hyp) end
  token.set_macro('lang' .. tag:gsub('-', ''), tostring(lang.id(l)))
end
