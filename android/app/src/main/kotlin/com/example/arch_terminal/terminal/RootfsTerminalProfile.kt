package com.example.arch_terminal.terminal

import java.io.File

/** Installs an interactive Bash profile with ANSI styling interpreted by xterm, not stored as copied text. */
internal object RootfsTerminalProfile {
    private const val FILE_NAME = "99-arch-terminal-prompt.sh"
    private const val CONTENT = """# Managed by Arch Terminal. Applies only to interactive Bash sessions.
export TERM="${'$'}{TERM:-xterm-256color}"
export CLICOLOR=1
export COLORTERM=truecolor
export SYSTEMD_COLORS=1
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01'
export GREP_COLORS='ms=01;38;5;208:fn=01;38;5;45:ln=01;38;5;244:se=01;38;5;244'
export PYTHON_COLORS=1
export LESS='-R'
export LESS_TERMCAP_md=$'\e[1;38;5;208m'
export LESS_TERMCAP_so=$'\e[38;5;16;48;5;75m'
export LESS_TERMCAP_us=$'\e[4;38;5;45m'
case $- in
  *i*)
    if command -v dircolors >/dev/null 2>&1; then
      eval "$(dircolors -b 2>/dev/null)"
    fi
    __arch_terminal_prompt_command() {
      local last_status="${'$'}?"
      local status_mark='\[\e[1;38;5;40m\]✓\[\e[0m\]'
      if [ "${'$'}last_status" -ne 0 ]; then
        status_mark="\[\e[1;38;5;196m\]✗ ${'$'}last_status\[\e[0m\]"
      fi
      PS1="${'$'}status_mark \[\e[1;38;5;196m\][\u@\h \[\e[38;5;45m\]\w\[\e[1;38;5;196m\]]#\[\e[0m\] "
    }
    PROMPT_COMMAND=__arch_terminal_prompt_command
    alias ls='ls --color=auto'
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'
    alias grep='grep --color=auto'
    alias egrep='egrep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias pacman='pacman --color=auto'
    alias diff='diff --color=auto'
    alias ip='ip --color=auto'
    alias git='git -c color.ui=auto'
    alias rg='rg --color=auto'
    # Read-only guest facts for the optional local AI environment snapshot.
    # Flutter passes a unique token and suppresses only this sentinel output.
    __arch_terminal_env_probe() {
      local token="${'$'}1"
      [ -n "${'$'}token" ] || return 2
      printf '\n__ARCH_TERMINAL_ENV_BEGIN_%s__\n' "${'$'}token"
      {
        printf 'user='; id -un 2>/dev/null || printf 'unknown'; printf '\n'
        printf 'uid='; id -u 2>/dev/null || printf 'unknown'; printf '\n'
        printf 'architecture='; uname -m 2>/dev/null || printf 'unknown'; printf '\n'
        printf 'os_name='; if [ -r /etc/os-release ]; then . /etc/os-release; printf '%s' "${'$'}{PRETTY_NAME:-${'$'}{NAME:-unknown}}"; else printf 'unknown'; fi; printf '\n'
        printf 'pacman='; if command -v pacman >/dev/null 2>&1; then printf 'yes'; else printf 'no'; fi; printf '\n'
        printf 'pacman_packages='; if command -v pacman >/dev/null 2>&1; then pacman -Qq 2>/dev/null | wc -l | tr -d ' '; else printf '0'; fi; printf '\n'
        printf 'repo_configured='; if [ -r /etc/pacman.d/mirrorlist ] && grep -q '^[[:space:]]*Server[[:space:]]*=' /etc/pacman.d/mirrorlist 2>/dev/null; then printf 'yes'; else printf 'no'; fi; printf '\n'
        printf 'repo_mirror='; if [ -r /etc/pacman.d/mirrorlist ]; then sed -n 's/^[[:space:]]*Server[[:space:]]*=[[:space:]]*//p' /etc/pacman.d/mirrorlist | head -n 1; fi; printf '\n'
        printf 'repo_names='; if [ -r /etc/pacman.conf ]; then sed -n 's/^[[:space:]]*\[\([^]]*\)\][[:space:]]*$/\1/p' /etc/pacman.conf | grep -v '^options$' | tr '\n' ',' | sed 's/,$//'; fi; printf '\n'
        printf 'repo_database_count='; if [ -d /var/lib/pacman/sync ]; then find /var/lib/pacman/sync -maxdepth 1 -type f -name '*.db' 2>/dev/null | wc -l | tr -d ' '; else printf '0'; fi; printf '\n'
        printf 'pwd='; pwd 2>/dev/null || printf 'unknown'; printf '\n'
        printf 'root_free_kib='; df -Pk / 2>/dev/null | awk 'NR==2 {print ${'$'}4; exit}'; printf '\n'
        printf 'storage_bound='; if [ -d /sdcard ]; then printf 'yes'; else printf 'no'; fi; printf '\n'
      } 2>/dev/null
      printf '__ARCH_TERMINAL_ENV_END_%s__\n' "${'$'}token"
    }
    # The minimal Arch RootFS runs the terminal as root and may not ship sudo.
    # Keep `sudo command` compatible without changing behavior for non-root users.
    if [ "$(id -u)" -eq 0 ] && ! command -v sudo >/dev/null 2>&1; then
      sudo() {
        if [ "$#" -eq 0 ]; then
          printf '%s\\n' 'sudo: a command is required' >&2
          return 1
        fi
        command "$@"
      }
    fi
  ;;
esac
"""

    fun apply(root: File) {
        val directory = File(root, "etc/profile.d")
        check(directory.exists() || directory.mkdirs()) { "Unable to create guest profile directory" }
        File(directory, FILE_NAME).writeText(CONTENT)
    }

    fun isConfigured(root: File): Boolean = File(root, "etc/profile.d/$FILE_NAME")
        .takeIf { it.isFile }
        ?.readText()
        ?.let { it.contains("PROMPT_COMMAND=__arch_terminal_prompt_command") && it.contains("pacman --color=auto") && it.contains("GREP_COLORS=") && it.contains("COLORTERM=truecolor") && it.contains("sudo()") }
        ?: false
}
