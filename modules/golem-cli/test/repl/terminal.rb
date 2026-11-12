# R4/R7: Run with ruby terminal.rb /absolute/path/to/golem on a POSIX terminal.
require "pty"
require "timeout"
require "tmpdir"

binary = File.realpath(ARGV.fetch(0))
Timeout.timeout(30) do
  Dir.mktmpdir do |dir|
    Dir.mkdir(File.join(dir, "library"))
    File.write(File.join(dir, "library", "names.emet"), "pub add :: Nat -> Nat\nadd n = n + 2\n")
    stdout = File.join(dir, "values")
    # Keep stdout separate so a prompt or a candidate written there fails the test.
    PTY.spawn({"TERM" => "xterm"}, "sh", "-c", 'exec "$1" repl emet >"$2"', "repl-test", binary, stdout, chdir: dir) do |reader, writer, pid|
      wait_for = lambda do |marker|
        text = +""
        text << reader.readpartial(4096) until text.include?(marker)
        text
      end
      prompt = "\e[?1h\e=emet> "
      wait_for.call(prompt)
      writer.write("1 +\r")
      wait_for.call("....> ")
      writer.write("\x03")
      wait_for.call(prompt)
      writer.write("twice :: Nat -> Nat\r")
      wait_for.call("....> ")
      writer.write("twice n = n + n\r")
      wait_for.call("....> ")
      writer.write("\r")
      wait_for.call(prompt)
      # Leave the argument after the cursor when Tab replaces the prefix.
      writer.write("twi 3\e[D\e[D\t\r")
      wait_for.call(prompt)
      writer.write("import \"lib\tnam\t\"\r")
      wait_for.call(prompt)
      writer.write("ad\t 5\r")
      wait_for.call(prompt)
      writer.write("twin :: Nat -> Nat\r")
      wait_for.call("....> ")
      writer.write("twin n = n + 1\r")
      wait_for.call("....> ")
      writer.write("\r")
      wait_for.call(prompt)
      writer.write("twi\t\t")
      choices = wait_for.call("twin")
      choices << wait_for.call("twice") unless choices.include?("twice")
      writer.write("\x03")
      wait_for.call(prompt)
      # A prefix with no match remains editable.
      writer.write("unmatched\t\x15")
      writer.write("9\r")
      wait_for.call(prompt)
      writer.write("\x04")
      begin
        reader.readpartial(4096) while true
      rescue EOFError, Errno::EIO
        # The slave side closed after the terminal settings were restored.
      end
      _, status = Process.wait2(pid)
      raise "session exited with #{status}" unless status.success?
      values = File.read(stdout)
      raise "unexpected stdout: #{values.inspect}" unless values == "=> 6\n=> 7\n=> 9\n"
    end
  end
end
