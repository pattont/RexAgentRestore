class RexAgentRestore < Formula
  desc "Resume Claude Code, Codex, and Grok Build chats when Rex restores your panes"
  homepage "https://github.com/pattont/RexAgentRestore"
  url "https://github.com/pattont/RexAgentRestore/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "8f840187f6e7a360878c97de6c73c27eaf60cf9130d006ec62f255923fa0f3a0"
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

      It adds a SessionStart hook to Claude Code, Codex, and Grok Build, a line
      to your ~/.zshrc, and "Resume Saved Agent Chats" actions to Rex. Every
      file it changes is backed up first. Undo it with:
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
