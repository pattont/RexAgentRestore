class RexAgentRestore < Formula
  desc "Resume coding agent chats (Claude Code, Codex, OpenCode, ...) after Rex restarts"
  homepage "https://github.com/pattont/RexAgentRestore"
  url "https://github.com/pattont/RexAgentRestore/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "36b6bfa7692e2007d26f0fc9d91214458ae5aed13513d76b740e0e3347d1d76f"
  license "MIT"
  head "https://github.com/pattont/RexAgentRestore.git", branch: "main"

  depends_on "jq"

  def install
    bin.install "bin/rex-agent-restore"
    pkgshare.install Dir["share/rex-agent-restore/*"]
  end

  def caveats
    <<~EOS
      Finish the setup with one command:
        rex-agent-restore install

      It finds the coding agents you have (Claude Code, Codex, OpenCode, Gemini
      CLI, Cursor Agent, and more), adds a hook or plugin to each, a line to
      your ~/.zshrc, and palette actions to Rex. Files are backed up first.

      Using Codex? Run /hooks in Codex once and approve "Rex Agent Restore".
      Before your first Rex restart, save the chats already open:
        rex-agent-restore capture
      Undo everything with:
        rex-agent-restore uninstall
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/rex-agent-restore version")

    ENV["HOME"] = testpath
    (testpath/".claude").mkpath
    system bin/"rex-agent-restore", "install", "--agents", "claude", "--no-shell", "--no-rex"
    assert_match "hook claude", (testpath/".claude/settings.json").read

    # The hook records nothing (and prints nothing) outside Rex.
    output = pipe_output("#{bin}/rex-agent-restore hook claude",
                         '{"hook_event_name":"SessionStart","session_id":"x"}')
    assert_empty output
  end
end
