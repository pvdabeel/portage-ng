/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> IPCCLIENT
Native Unix-domain IPC client for a portage-ng daemon.

Functional parity with `Source/Application/Client/ipclient.pl`: request
streaming, env forward, `--status`, `--cmd halt|relaunch`, `--shell` reject,
and autostart via `portage-ng-dev --mode daemon --background`. This binary is
the `ng-ipc-cpp` client used by `pm-bench`. It does not load SWI-Prolog or the
knowledge base; the daemon holds the KB.

This file is a standalone entry point. The Prolog counterpart is the
canonical protocol description; this client reimplements the same wire
format in C++ so process boot stays off the SWI runtime.

Wire protocol (same as `ipc.pl` / `ipclient.pl`):

```
client -> daemon:  request([Args...], Cols, Rows, [Name-Value, ...]).
daemon -> client:  <stdout/stderr UTF-8 stream> + NUL "EXIT:<code>\n"
```

Authentication relies on Unix file permissions (socket mode 0600 inside a
0700 owner-verified runtime directory; see `daemon:ensure_runtime_dir/0`).

Launch:

```
make ipcclient
Source/Application/Wrapper/ipcclient --mode ipc --pretend <pkg>
```

@see Source/Application/Client/ipclient.pl
@see Source/Application/Mode/ipc.pl
@see Source/Application/Mode/daemon.pl
*/

#include <cerrno>
#include <climits>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <string>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/un.h>
#include <unistd.h>

namespace {

// =============================================================================
//  IPCCLIENT declarations
// =============================================================================

// -----------------------------------------------------------------------------
//  Paths (mirrors config:daemon_* without loading config.pl)
// -----------------------------------------------------------------------------

constexpr char kSentinel[] = "EXIT:";

// Same names as ipclient:forwarded_env_var/1. Only vars present in the
// client environment are encoded into the request term.
const char* kForwardedEnv[] = {
    "USE",
    "ACCEPT_KEYWORDS",
    "ACCEPT_LICENSE",
    "PYTHON_TARGETS",
    "PYTHON_SINGLE_TARGET",
    "RUBY_TARGETS",
    "RUBY_SINGLE_TARGET",
    "LUA_SINGLE_TARGET",
    "PERL_FEATURES",
    "LLVM_SLOT",
    "VIDEO_CARDS",
    "INPUT_DEVICES",
    "CPU_FLAGS_X86",
    "APACHE2_MODULES",
    "APACHE2_MPMS",
};

std::string g_argv0;


//! ipcclient:runtime_dir(-Dir)
//
// XDG_RUNTIME_DIR when set, otherwise `/tmp/portage-ng-$USER`.

std::string runtime_dir() {
  const uid_t euid = geteuid();
  if (euid == 0)
    return "/var/run/portage-ng";
  if (const char* xdg = std::getenv("XDG_RUNTIME_DIR");
      xdg && *xdg && xdg[0] == '/')
    return std::string(xdg) + "/portage-ng";
  return std::string("/tmp/portage-ng-") + std::to_string(euid);
}


//! ipcclient:socket_path(-Path)

std::string socket_path() { return runtime_dir() + "/portage-ng.sock"; }


//! ipcclient:pid_path(-Path)

std::string pid_path() { return runtime_dir() + "/portage-ng.pid"; }


//! ipcclient:file_exists(+Path) is semidet.

bool file_exists(const std::string& path) {
  return access(path.c_str(), F_OK) == 0;
}


bool socket_connectable(const std::string& path) {
  int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0)
    return false;
  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  if (path.size() >= sizeof(addr.sun_path)) {
    ::close(fd);
    return false;
  }
  std::memcpy(addr.sun_path, path.c_str(), path.size() + 1);
  const bool ok =
      ::connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0;
  ::close(fd);
  return ok;
}


// -----------------------------------------------------------------------------
//  Request encoding
// -----------------------------------------------------------------------------

//! ipcclient:quote_atom(+S, -Quoted)
//
// Always-quoted Prolog atom (`~q`-compatible; always valid for `read_term`).

std::string quote_atom(const std::string& s) {
  std::string out;
  out.reserve(s.size() + 2);
  out.push_back('\'');
  for (unsigned char c : s) {
    if (c == '\'')
      out.push_back('\'');
    out.push_back(static_cast<char>(c));
  }
  out.push_back('\'');
  return out;
}


//! ipcclient:tty_size(-Cols, -Rows)
//
// Same defaults as `console:local_tty_size/2` / ipclient (80 rows, 160 cols).

void tty_size(int& cols, int& rows) {
  cols = 160;
  rows = 80;
  winsize ws{};
  if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0 &&
      ws.ws_row > 0) {
    cols = ws.ws_col;
    rows = ws.ws_row;
  }
}


//! ipcclient:build_env_term(-Env)
//
// Prolog list of `Name-Value` pairs. `_CLIENT_IS_TTY-true` is added when
// stdout is a tty so the daemon can decide whether to emit ANSI.

std::string build_env_term() {
  std::string env = "[";
  bool first = true;
  auto add = [&](const std::string& name, const std::string& value) {
    if (!first)
      env.push_back(',');
    first = false;
    env += quote_atom(name);
    env.push_back('-');
    env += quote_atom(value);
  };
  if (isatty(STDOUT_FILENO))
    add("_CLIENT_IS_TTY", "true");
  for (const char* name : kForwardedEnv) {
    if (const char* val = std::getenv(name); val)
      add(name, val);
  }
  env.push_back(']');
  return env;
}


//! ipcclient:build_request(+Argc, +Argv, -Request)
//
// Encodes `request(Args, Cols, Rows, Env).` from argv (skipping argv[0]).

std::string build_request(int argc, char** argv) {
  std::string args = "[";
  for (int i = 1; i < argc; ++i) {
    if (i > 1)
      args.push_back(',');
    args += quote_atom(argv[i]);
  }
  args.push_back(']');

  int cols = 160, rows = 80;
  tty_size(cols, rows);

  std::string req = "request(";
  req += args;
  req += ", ";
  req += std::to_string(cols);
  req += ", ";
  req += std::to_string(rows);
  req += ", ";
  req += build_env_term();
  req += ").\n";
  return req;
}


// -----------------------------------------------------------------------------
//  Connect + request
// -----------------------------------------------------------------------------

//! ipcclient:connect_socket(+Path, -Fd)
//
// Connects to the Unix-domain daemon socket. Returns a file descriptor, or
// -1 after printing an error.

int connect_socket(const std::string& path) {
  int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    std::cerr << "Error: socket(): " << std::strerror(errno) << '\n';
    return -1;
  }
  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  if (path.size() >= sizeof(addr.sun_path)) {
    std::cerr << "Error: socket path too long: " << path << '\n';
    ::close(fd);
    return -1;
  }
  std::memcpy(addr.sun_path, path.c_str(), path.size() + 1);
  if (::connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
    std::cerr << "Error: No daemon running (socket " << path
              << " not found).\n"
              << "Start one with: portage-ng --mode daemon\n";
    ::close(fd);
    return -1;
  }
  return fd;
}


//! ipcclient:write_all(+Fd, +Data) is semidet.

bool write_all(int fd, const std::string& data) {
  const char* p = data.data();
  size_t left = data.size();
  while (left > 0) {
    ssize_t n = ::write(fd, p, left);
    if (n < 0) {
      if (errno == EINTR)
        continue;
      std::cerr << "Error: write(): " << std::strerror(errno) << '\n';
      return false;
    }
    p += n;
    left -= static_cast<size_t>(n);
  }
  return true;
}


// -----------------------------------------------------------------------------
//  Stream response (NUL EXIT:<code> sentinel)
// -----------------------------------------------------------------------------

//! ipcclient:read_retry(+Fd, -Buf, +Cap, -N)
//
// Reads up to Cap bytes. Retries EINTR. Returns bytes read, 0 on EOF, or
// -1 on error (errno preserved).

ssize_t read_retry(int fd, char* buf, size_t cap) {
  for (;;) {
    ssize_t n = ::read(fd, buf, cap);
    if (n < 0 && errno == EINTR)
      continue;
    return n;
  }
}


//! ipcclient:emit_codes(+Data, +N)

void emit_codes(const char* data, size_t n) {
  if (n == 0)
    return;
  fwrite(data, 1, n, stdout);
  fflush(stdout);
}


//! ipcclient:emit_codes(+Codes)

void emit_codes(const std::string& codes) {
  emit_codes(codes.data(), codes.size());
}


//! ipcclient:connection_lost_error

void connection_lost_error() {
  std::cerr
      << "Error: daemon closed the connection without an exit status.\n";
}


//! ipcclient:parse_exit_code(+Digits, -ExitCode)

int parse_exit_code(const std::string& digits) {
  if (digits.empty())
    return 1;
  char* end = nullptr;
  long v = std::strtol(digits.c_str(), &end, 10);
  if (end == digits.c_str() || *end != '\0')
    return 1;
  return static_cast<int>(v);
}


//! ipcclient:collect_exit_code(+Fd, +Acc, -ExitCode)
//
// Reads until a newline after `EXIT:` and parses the digits.

int collect_exit_code(int fd, std::string acc) {
  char buf[8192];
  for (;;) {
    auto nl = acc.find('\n');
    if (nl != std::string::npos)
      return parse_exit_code(acc.substr(0, nl));
    ssize_t n = read_retry(fd, buf, sizeof(buf));
    if (n < 0)
      return 1;
    if (n == 0)
      return parse_exit_code(acc);
    acc.append(buf, static_cast<size_t>(n));
  }
}


//! ipcclient:is_partial_sentinel(+Tail) is semidet.
//
// True when Tail is a (possibly empty) proper prefix of `EXIT:`.

bool is_partial_sentinel(const std::string& tail) {
  const size_t n = sizeof(kSentinel) - 1;
  return tail.size() < n &&
         tail.compare(0, tail.size(), kSentinel, tail.size()) == 0;
}


//! ipcclient:match_sentinel(+Fd, +Tail, ?Carry, -ExitCode) is semidet.
//
// After a NUL: full `EXIT:` collects the code; a prefix waits for more;
// anything else is payload. False means the NUL was payload — Carry holds
// the leftover bytes and the caller resumes scanning.

bool match_sentinel(int fd, std::string tail, std::string& carry,
                    int& exit_code) {
  char buf[8192];
  const size_t slen = sizeof(kSentinel) - 1;
  for (;;) {
    if (tail.size() >= slen && tail.compare(0, slen, kSentinel) == 0) {
      exit_code = collect_exit_code(fd, tail.substr(slen));
      return true;
    }
    if (!is_partial_sentinel(tail)) {
      emit_codes("\0", 1);
      carry = std::move(tail);
      return false;
    }
    ssize_t n = read_retry(fd, buf, sizeof(buf));
    if (n < 0) {
      exit_code = 1;
      return true;
    }
    if (n == 0) {
      emit_codes("\0", 1);
      emit_codes(tail);
      connection_lost_error();
      exit_code = 1;
      return true;
    }
    tail.append(buf, static_cast<size_t>(n));
  }
}


//! ipcclient:scan_output(+Fd, ?Carry, -ExitCode) is semidet.
//
// Emits bytes before each NUL and tries `match_sentinel`. True when an
// exit code is decided. False when the buffer has no NUL left.

bool scan_output(int fd, std::string& carry, int& exit_code) {
  for (;;) {
    auto nul = carry.find('\0');
    if (nul == std::string::npos) {
      emit_codes(carry);
      carry.clear();
      return false;
    }
    emit_codes(carry.data(), nul);
    std::string tail = carry.substr(nul + 1);
    carry.clear();
    if (match_sentinel(fd, std::move(tail), carry, exit_code))
      return true;
  }
}


//! ipcclient:stream_response(+Fd, -ExitCode)
//
// Copies daemon output to stdout until a NUL-prefixed `EXIT:<code>\n`
// sentinel. A NUL that is not followed by the sentinel is treated as
// payload. Returns the daemon exit code, or 1 on a truncated stream.

int stream_response(int fd) {
  std::string carry;
  char buf[8192];
  for (;;) {
    ssize_t n = read_retry(fd, buf, sizeof(buf));
    if (n < 0) {
      std::cerr << "Error: read(): " << std::strerror(errno) << '\n';
      return 1;
    }
    if (n == 0) {
      emit_codes(carry);
      connection_lost_error();
      return 1;
    }
    carry.append(buf, static_cast<size_t>(n));
    int code = 0;
    if (scan_output(fd, carry, code))
      return code;
  }
}


// -----------------------------------------------------------------------------
//  Status / commands / autostart
// -----------------------------------------------------------------------------

//! ipcclient:wait_for_file(+Path, +Retries)
//
// Polls every 100 ms until Path exists or Retries is exhausted.

void wait_for_file(const std::string& path, int retries) {
  for (int i = 0; i < retries; ++i) {
    if (file_exists(path))
      return;
    usleep(100000);
  }
}


//! ipcclient:wait_for_socket_gone(+Path, +Retries)
//
// Polls every 100 ms until Path is gone or Retries is exhausted.

void wait_for_socket_gone(const std::string& path, int retries) {
  for (int i = 0; i < retries; ++i) {
    if (!file_exists(path))
      return;
    usleep(100000);
  }
}


//! ipcclient:autostart_enabled is semidet.
//
// Same default as `config:daemon_autostart(true)`. Override with
// `PORTAGE_NG_IPC_AUTOSTART=0|false` (checked only when the socket is missing).

bool autostart_enabled() {
  const char* v = std::getenv("PORTAGE_NG_IPC_AUTOSTART");
  if (!v)
    return true;
  return std::strcmp(v, "0") != 0 && std::strcmp(v, "false") != 0;
}


//! ipcclient:daemon_wrapper(-Wrapper)
//
// Absolute path to `portage-ng-dev`, used to start/relaunch the daemon in a
// child process. `PORTAGE_NG_DEV` wins; otherwise a sibling of this binary
// (including after `realpath` of argv0 when invoked via PATH).

std::string daemon_wrapper() {
  if (const char* env = std::getenv("PORTAGE_NG_DEV"); env && *env) {
    if (access(env, X_OK) == 0)
      return env;
  }
  std::string base = g_argv0.empty() ? "." : g_argv0;
  auto slash = base.rfind('/');
  std::string dir = (slash == std::string::npos) ? "." : base.substr(0, slash);
  std::string cand = dir + "/portage-ng-dev";
  if (access(cand.c_str(), X_OK) == 0)
    return cand;
  char resolved[PATH_MAX];
  if (!g_argv0.empty() && realpath(g_argv0.c_str(), resolved)) {
    std::string abs(resolved);
    slash = abs.rfind('/');
    dir = (slash == std::string::npos) ? "." : abs.substr(0, slash);
    cand = dir + "/portage-ng-dev";
    if (access(cand.c_str(), X_OK) == 0)
      return cand;
  }
  return {};
}


//! ipcclient:start_daemon_background is det.
//
// Starts the full daemon via `portage-ng-dev --mode daemon --background`.
// The child loads the knowledge base; this client stays ultralight.
// stdout/stderr must be `/dev/null` (not pipes): the `--background` child
// prints status while we wait on `waitpid`; piping both invites deadlock
// when the pipe buffer fills before we drain — same as `ipclient.pl`.

int start_daemon_background() {
  const std::string wrapper = daemon_wrapper();
  if (wrapper.empty()) {
    std::cerr
        << "Error: cannot locate portage-ng-dev to start the daemon.\n"
        << "Set PORTAGE_NG_DEV or start one with: portage-ng --mode daemon\n";
    return 1;
  }
  std::cout << "Starting daemon in background...\n";
  pid_t pid = fork();
  if (pid < 0) {
    std::cerr << "Error: fork(): " << std::strerror(errno) << '\n';
    return 1;
  }
  if (pid == 0) {
    int devnull = open("/dev/null", O_RDWR);
    if (devnull >= 0) {
      dup2(devnull, STDIN_FILENO);
      dup2(devnull, STDOUT_FILENO);
      dup2(devnull, STDERR_FILENO);
      if (devnull > STDERR_FILENO)
        close(devnull);
    }
    execl(wrapper.c_str(), wrapper.c_str(), "--mode", "daemon", "--background",
         static_cast<char*>(nullptr));
    _exit(127);
  }
  int status = 0;
  while (waitpid(pid, &status, 0) < 0) {
    if (errno != EINTR) {
      std::cerr << "Error: waitpid(): " << std::strerror(errno) << '\n';
      return 1;
    }
  }
  if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
    std::cerr << "Error: failed to start daemon (status " << status << ").\n";
    return 1;
  }
  const std::string sock = socket_path();
  wait_for_file(sock, 600);
  if (socket_connectable(sock)) {
    std::cout << "Daemon ready.\n";
    return 0;
  }
  std::cerr << "Warning: daemon may not have started.\n";
  return 0;
}


//! ipcclient:maybe_autostart is det.
//
// If no daemon socket exists and autostart is enabled, start one in a child
// process. The hot path (socket already present) does no fork.

int maybe_autostart() {
  if (socket_connectable(socket_path()))
    return 0;
  if (!autostart_enabled())
    return 0;
  return start_daemon_background();
}


//! ipcclient:status is semidet.

int cmd_status() {
  const std::string sock = socket_path();
  const std::string pidf = pid_path();
  if (!socket_connectable(sock)) {
    std::cout << "No daemon running.\n";
    return 1;
  }
  std::ifstream in(pidf);
  std::string pid;
  if (in && std::getline(in, pid) && !pid.empty()) {
    while (!pid.empty() && (pid.back() == '\n' || pid.back() == ' '))
      pid.pop_back();
    std::cout << "Daemon running (PID " << pid << ", socket " << sock << ")\n";
  } else {
    std::cout << "Daemon socket exists (" << sock << ") but no PID file.\n";
  }
  return 0;
}


//! ipcclient:cmd_halt is det.
//
// Sends `shutdown.` to the daemon. When no socket exists, prints an error
// and returns 0 — same as `ipclient:send_command_(halt)`.

int cmd_halt() {
  const std::string sock = socket_path();
  if (!socket_connectable(sock)) {
    std::cerr << "No daemon running.\n";
    return 0;
  }
  int fd = connect_socket(sock);
  if (fd < 0)
    return 1;
  if (!write_all(fd, "shutdown.\n")) {
    ::close(fd);
    return 1;
  }
  char buf[256];
  while (::read(fd, buf, sizeof(buf)) > 0) {
  }
  ::close(fd);
  std::cout << "Daemon stopped.\n";
  return 0;
}


//! ipcclient:relaunch is det.
//
// Stops the daemon and starts a new one via the full-stack wrapper child.

int cmd_relaunch() {
  cmd_halt();
  sleep(1);
  wait_for_socket_gone(socket_path(), 50);
  return start_daemon_background();
}


//! ipcclient:send_command(+Cmd)
//
// Cmd is `halt` or `relaunch`.

int send_command(const std::string& cmd) {
  if (cmd == "halt")
    return cmd_halt();
  if (cmd == "relaunch")
    return cmd_relaunch();
  std::cerr << "Unknown command: " << cmd << ". Use halt or relaunch.\n";
  return 1;
}


// -----------------------------------------------------------------------------
//  Entry
// -----------------------------------------------------------------------------

//! ipcclient:usage(+Argv0)

void usage(const char* argv0) {
  std::cerr
      << "Usage:\n"
      << "  " << argv0 << " --mode ipc --pretend <pkg>\n"
      << "  " << argv0 << " --status\n"
      << "  " << argv0 << " --cmd halt|relaunch\n"
      << "\n"
      << "Socket: " << socket_path() << "\n";
}


//! ipcclient:find_cmd(+Argc, +Argv, -Cmd)
//
// Parses `--cmd NAME` or `--cmd=NAME` from argv. Empty when absent.

std::string find_cmd(int argc, char** argv) {
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "--cmd") == 0) {
      if (i + 1 < argc)
        return argv[i + 1];
      return {};
    }
    if (std::strncmp(argv[i], "--cmd=", 6) == 0)
      return argv[i] + 6;
  }
  return {};
}


//! ipcclient:has_flag(+Argc, +Argv, +Flag) is semidet.

bool has_flag(int argc, char** argv, const char* flag) {
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], flag) == 0)
      return true;
  }
  return false;
}

} // namespace


//! ipcclient:main(+Argc, +Argv)
//
// Dispatches `--status` / `--cmd` / `--shell`, optionally autostarts the
// daemon, then connects and streams one request. Always exits with the
// daemon status (or 1 on a client-side error).

int main(int argc, char** argv) {
  g_argv0 = argc > 0 ? argv[0] : "";

  if (argc < 2) {
    usage(argv[0]);
    return 1;
  }

  if (has_flag(argc, argv, "--shell")) {
    std::cerr << "Error: --shell is not supported in ipc mode. "
                 "Use --mode standalone --shell instead.\n";
    return 1;
  }
  if (has_flag(argc, argv, "-h") || has_flag(argc, argv, "--help")) {
    usage(argv[0]);
    return 0;
  }
  if (has_flag(argc, argv, "--status"))
    return cmd_status();

  const std::string cmd = find_cmd(argc, argv);
  if (!cmd.empty())
    return send_command(cmd);
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "--cmd") == 0) {
      std::cerr << "Error: --cmd requires an argument\n";
      return 1;
    }
  }

  if (maybe_autostart() != 0)
    return 1;

  const std::string sock = socket_path();
  if (!socket_connectable(sock)) {
    std::cerr << "Error: No daemon running (socket " << sock
              << " not found).\n"
              << "Start one with: portage-ng --mode daemon\n";
    return 1;
  }

  int fd = connect_socket(sock);
  if (fd < 0)
    return 1;

  const std::string req = build_request(argc, argv);
  if (!write_all(fd, req)) {
    ::close(fd);
    return 1;
  }

  const int code = stream_response(fd);
  ::close(fd);
  return code;
}
