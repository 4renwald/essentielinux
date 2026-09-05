# System privilege escalation

- For a direct command that must run as root, request the coding-agent host's
  normal execution approval and run the exact executable with `pkexec`. The
  desktop Polkit agent will ask the user to authenticate graphically.
- Do not use `sudo` from a noninteractive agent shell and never request, read,
  store, or pipe the user's password.
- Keep the privileged command as narrow as possible. Do not use
  `pkexec sh -c`, `pkexec bash -c`, or an unrestricted root shell unless shell
  evaluation is truly required and the user has approved the exact script.
- Do not wrap a command that already manages privilege elevation. Package AUR
  build steps must remain unprivileged; elevate only the final system package
  operation when needed.
- Agent tool approval and operating-system authorization are separate. A tool
  may first ask permission to leave its sandbox, followed by the Polkit popup.
