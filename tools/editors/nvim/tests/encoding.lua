-- I1: golem lsp, attached to a Neovim client that offers utf-8, makes the
-- offset_encoding of the client utf-8; a client that offers utf-16 alone
-- gets utf-16 (golem-lsp ADR 0002, docs/adr/0231)
return function(t)
  t.edit('a.gm')
  local client = t.start_lsp(nil)
  t.expect('the offset_encoding with the capabilities of Neovim', client.offset_encoding, 'utf-8', 'utf-16')
  client:stop(true)

  t.edit('b.gm')
  local caps = vim.lsp.protocol.make_client_capabilities()
  caps.general.positionEncodings = { 'utf-16' }
  local only16 = t.start_lsp(caps)
  t.check(only16.offset_encoding == 'utf-16', 'the offset_encoding with utf-16 alone: got ' .. vim.inspect(only16.offset_encoding) .. ', expected "utf-16"')
end
