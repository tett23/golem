-- The harness of the tests of Neovim with golem lsp (docs/adr/0231).
-- test.sh runs every test in a Neovim of its own:
--
--   nvim --headless --clean -u tools/editors/nvim/init.lua
--
-- with these variables:
--
--   GOLEM_NVIM_TEST    the name of the test, a file tests/<name>.lua
--   GOLEM_NVIM_WORK    the copy of modules/golem-lsp/test/fixtures/
--   GOLEM_NVIM_INVERT  1 to invert the one expectation the test marks
--                      (test.sh --self-test)
--   GOLEM              the executable of golem
--
-- A test is a function of the harness t; it runs in a coroutine, so that
-- it can wait for the server and for the keys it types. It passes when it
-- returns, and fails at the first failed check: the harness writes
-- "nvim: <name>: FAILED: ..." to the standard error and exits with
-- :cquit 1. A test that takes more than 60 seconds fails too.
local name = os.getenv('GOLEM_NVIM_TEST') or ''
local here = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))

local t = {
  name = name,
  work = os.getenv('GOLEM_NVIM_WORK') or '',
  golem = os.getenv('GOLEM') or 'golem',
  inverted = os.getenv('GOLEM_NVIM_INVERT') == '1',
  editors = vim.fs.dirname(here),
}
t.proj = t.work .. '/proj'

local co
local finished = false

local function finish(err)
  if finished then
    return
  end
  finished = true
  if err then
    io.stderr:write(('nvim: %s: FAILED: %s\n'):format(name, err))
    vim.cmd.cquit(1)
  else
    io.stdout:write(('nvim: %s: ok\n'):format(name))
    vim.cmd('qall!')
  end
end

-- a failed check ends the test; an error of Lua is a failure too
function t.fail(msg)
  error({ golem_failure = msg }, 0)
end

function t.check(ok, msg)
  if not ok then
    t.fail(msg)
  end
end

-- the expectation that --self-test inverts: under GOLEM_NVIM_INVERT the
-- test expects `inverted` instead of `expected`, and so must fail
function t.expect(what, actual, expected, inverted)
  if t.inverted then
    expected = inverted
  end
  if not vim.deep_equal(actual, expected) then
    t.fail(('%s: got %s, expected %s'):format(what, vim.inspect(actual), vim.inspect(expected)))
  end
end

-- the same for a predicate: under GOLEM_NVIM_INVERT the test expects it
-- not to hold
function t.expect_that(what, ok)
  if t.inverted then
    ok = not ok
  end
  if not ok then
    t.fail(what .. (t.inverted and ' (inverted)' or ''))
  end
end

local function resume(...)
  local ok, err = coroutine.resume(co, ...)
  if not ok then
    finish(type(err) == 'table' and err.golem_failure or debug.traceback(co, tostring(err)))
  elseif coroutine.status(co) == 'dead' then
    finish(nil)
  end
end

-- gives the main loop the control for ms milliseconds: the messages of the
-- server and the keys fed are handled meanwhile
function t.sleep(ms)
  vim.defer_fn(resume, ms)
  coroutine.yield()
end

function t.wait_until(what, pred, ms)
  local deadline = vim.uv.now() + (ms or 20000)
  while true do
    local v = pred()
    if v then
      return v
    end
    if vim.uv.now() > deadline then
      t.fail('timed out waiting for ' .. what)
    end
    t.sleep(20)
  end
end

-- types keys as if from the keyboard; they run once the test waits
function t.feed(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), 'n', false)
end

-- opens a file of the copied project in the current window
function t.edit(rel)
  local path = t.proj .. '/' .. rel
  if vim.api.nvim_buf_get_name(0) ~= path then
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
  return vim.api.nvim_get_current_buf()
end

-- starts golem lsp at the root of the copied project for the current
-- buffer, and waits for its initialization
function t.start_lsp(capabilities)
  local id = vim.lsp.start({
    name = 'golem',
    cmd = { t.golem, 'lsp' },
    root_dir = t.proj,
    capabilities = capabilities,
  })
  t.check(id ~= nil, 'vim.lsp.start returned nil')
  local client = t.wait_until('the initialization of golem lsp', function()
    local c = vim.lsp.get_client_by_id(id)
    return c and c.initialized and c
  end)
  return client
end

-- the diagnostics of a buffer once they satisfy pred
function t.diagnostics(buf, what, pred)
  return t.wait_until(what, function()
    local ds = vim.diagnostic.get(buf)
    return pred(ds) and ds
  end)
end

-- no messages of the modes in the output of the tests
vim.o.showmode = false
vim.opt.shortmess:append('c')

-- the file types of the README, but for the test of the README itself
if name ~= 'readme' then
  vim.filetype.add({ extension = { gm = 'golem', emet = 'emet' } })
end

local path = here .. '/tests/' .. name .. '.lua'
if name == '' or not vim.uv.fs_stat(path) then
  io.stderr:write(('nvim: no test %q in %s\n'):format(name, here .. '/tests'))
  vim.cmd.cquit(2)
  return
end
local test = dofile(path)
co = coroutine.create(function()
  test(t)
end)
vim.defer_fn(function()
  finish('timed out after 60 seconds')
end, 60000)
-- after the startup, so that the test runs in the main loop
vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = vim.schedule_wrap(resume) })
if vim.v.vim_did_enter == 1 then
  vim.schedule(resume)
end
