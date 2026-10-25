source "${${(%):-%x}:A:h}/../session-resume/resume.zsh"

# Accept either a Codex or Claude session UUID (or a unique prefix).
codex::resume() { _agent_session_resume codex "$@"; }
