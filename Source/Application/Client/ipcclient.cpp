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

The program is written to start quickly, because for a small request
starting the client takes longer than the daemon takes to answer. It does
not use the C++ stream and string classes and is built without exceptions
and run-time type information, so the system C library is the only library
it needs when it starts. The request and the answer are kept in buffers on
the stack. Memory is allocated only for a request longer than 4 KB, or for
an answer that contains NUL bytes of its own.

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
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

namespace {

// =============================================================================
//  IPCCLIENT declarations
// =============================================================================

constexpr char kSentinel[] = "EXIT:";
constexpr size_t kSentinelLen = sizeof(kSentinel) - 1;
constexpr size_t kStreamBufSize = 65536;

// The same names as ipclient:forwarded_env_vars/1. Only the variables that are
// set in the environment of the client are put in the request.
constexpr const char* kForwardedEnv[] = {
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


// -----------------------------------------------------------------------------
//  Byte buffer that starts on the stack
// -----------------------------------------------------------------------------

// A byte buffer that grows as needed. Its first 4 KB are part of the object
// itself, so a buffer declared in a function uses the stack and no memory is
// allocated until more than 4 KB is stored. When memory cannot be allocated
// the program exits with status 1.

class SmallBuf {
public:
  SmallBuf() : data_(inline_), size_(0), cap_(sizeof(inline_)) {}

  ~SmallBuf() {
    if (data_ != inline_)
      std::free(data_);
  }

  SmallBuf(const SmallBuf&) = delete;
  SmallBuf& operator=(const SmallBuf&) = delete;

  char* data() { return data_; }
  const char* data() const { return data_; }
  size_t size() const { return size_; }
  bool empty() const { return size_ == 0; }

  void clear() { size_ = 0; }

  bool reserve(size_t need) {
    if (need <= cap_)
      return true;
    size_t new_cap = cap_ * 2;
    while (new_cap < need)
      new_cap *= 2;
    char* p = nullptr;
    if (data_ == inline_) {
      p = static_cast<char*>(std::malloc(new_cap));
      if (!p)
        return false;
      std::memcpy(p, inline_, size_);
    } else {
      p = static_cast<char*>(std::realloc(data_, new_cap));
      if (!p)
        return false;
    }
    data_ = p;
    cap_ = new_cap;
    return true;
  }

  void push(char c) {
    if (!reserve(size_ + 1))
      _exit(1);
    data_[size_++] = c;
  }

  void append(const char* s, size_t n) {
    if (n == 0)
      return;
    if (!reserve(size_ + n))
      _exit(1);
    std::memcpy(data_ + size_, s, n);
    size_ += n;
  }

  void append_cstr(const char* s) { append(s, std::strlen(s)); }

  void append_uint(unsigned long v) {
    char tmp[32];
    size_t i = sizeof(tmp);
    do {
      tmp[--i] = static_cast<char>('0' + (v % 10));
      v /= 10;
    } while (v != 0);
    append(tmp + i, sizeof(tmp) - i);
  }

  // Appends s as a quoted Prolog atom, so that read_term/2 in the daemon gives
  // back exactly s. The text goes between single quotes. A single quote, a
  // backslash, a line feed and a carriage return are written as the escapes
  // \' \\ \n and \r, because inside a quoted atom a backslash starts an escape
  // and a line break is not allowed. Everything else is copied as it is, one
  // stretch at a time.
  void append_quoted_atom(const char* s) {
    push('\'');
    const char* run = s;
    for (const char* c = s;; ++c) {
      const char* escape = nullptr;
      switch (*c) {
        case '\0':
          append(run, static_cast<size_t>(c - run));
          push('\'');
          return;
        case '\'': escape = "\\'"; break;
        case '\\': escape = "\\\\"; break;
        case '\n': escape = "\\n"; break;
        case '\r': escape = "\\r"; break;
        default: continue;
      }
      append(run, static_cast<size_t>(c - run));
      append(escape, 2);
      run = c + 1;
    }
  }

private:
  char inline_[4096];
  char* data_;
  size_t size_;
  size_t cap_;
};


// -----------------------------------------------------------------------------
//  Low-level file descriptor output
// -----------------------------------------------------------------------------

bool write_all_fd(int fd, const char* data, size_t len) {
  const char* p = data;
  size_t left = len;
  while (left > 0) {
    ssize_t n = ::write(fd, p, left);
    if (n < 0) {
      if (errno == EINTR)
        continue;
      return false;
    }
    p += n;
    left -= static_cast<size_t>(n);
  }
  return true;
}


void write_out_cstr(const char* s) {
  write_all_fd(STDOUT_FILENO, s, std::strlen(s));
}


void write_err_cstr(const char* s) {
  write_all_fd(STDERR_FILENO, s, std::strlen(s));
}


// -----------------------------------------------------------------------------
//  Paths (mirrors runtimepath:daemon_runtime_dir/1 without loading config.pl)
// -----------------------------------------------------------------------------

struct Paths {
  char sock[PATH_MAX];
  char pid[PATH_MAX];
  size_t sock_len;
  sockaddr_un addr;
  bool addr_ok;
};


size_t build_runtime_dir(char* out, size_t cap) {
  const uid_t euid = geteuid();
  if (euid == 0) {
    constexpr char kRootDir[] = "/var/run/portage-ng";
    if (sizeof(kRootDir) > cap)
      return 0;
    std::memcpy(out, kRootDir, sizeof(kRootDir));
    return sizeof(kRootDir) - 1;
  }
  if (const char* xdg = std::getenv("XDG_RUNTIME_DIR");
      xdg && xdg[0] == '/') {
    size_t xlen = std::strlen(xdg);
    while (xlen > 1 && xdg[xlen - 1] == '/')
      --xlen;
    constexpr char kSub[] = "/portage-ng";
    const size_t prefix = (xlen == 1 && xdg[0] == '/') ? 0 : xlen;
    if (prefix + sizeof(kSub) > cap)
      return 0;
    if (prefix > 0)
      std::memcpy(out, xdg, prefix);
    std::memcpy(out + prefix, kSub, sizeof(kSub));
    return prefix + sizeof(kSub) - 1;
  }
  SmallBuf tmp;
  tmp.append_cstr("/tmp/portage-ng-");
  tmp.append_uint(static_cast<unsigned long>(euid));
  if (tmp.size() + 1 > cap)
    return 0;
  std::memcpy(out, tmp.data(), tmp.size());
  out[tmp.size()] = '\0';
  return tmp.size();
}


bool init_paths(Paths& p) {
  char dir[PATH_MAX];
  const size_t dlen = build_runtime_dir(dir, sizeof(dir));
  if (dlen == 0)
    return false;

  constexpr char kSockSuffix[] = "/portage-ng.sock";
  constexpr char kPidSuffix[] = "/portage-ng.pid";
  if (dlen + sizeof(kSockSuffix) > sizeof(p.sock) ||
      dlen + sizeof(kPidSuffix) > sizeof(p.pid))
    return false;

  std::memcpy(p.sock, dir, dlen);
  std::memcpy(p.sock + dlen, kSockSuffix, sizeof(kSockSuffix));
  p.sock_len = dlen + sizeof(kSockSuffix) - 1;

  std::memcpy(p.pid, dir, dlen);
  std::memcpy(p.pid + dlen, kPidSuffix, sizeof(kPidSuffix));

  std::memset(&p.addr, 0, sizeof(p.addr));
  p.addr.sun_family = AF_UNIX;
  if (p.sock_len < sizeof(p.addr.sun_path)) {
    std::memcpy(p.addr.sun_path, p.sock, p.sock_len + 1);
    p.addr_ok = true;
  } else {
    p.addr_ok = false;
  }
  return true;
}


bool file_exists(const char* path) { return ::access(path, F_OK) == 0; }


int open_unix_socket() {
#ifdef SOCK_CLOEXEC
  int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
#else
  int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
#endif
#ifdef SO_NOSIGPIPE
  if (fd >= 0) {
    const int one = 1;
    (void)::setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
  }
#endif
  return fd;
}


int try_connect(const Paths& p) {
  if (!p.addr_ok) {
    errno = ENAMETOOLONG;
    return -1;
  }
  int fd = open_unix_socket();
  if (fd < 0)
    return -1;
  if (::connect(fd, reinterpret_cast<const sockaddr*>(&p.addr),
                sizeof(p.addr)) == 0)
    return fd;
  const int saved = errno;
  ::close(fd);
  errno = saved;
  return -1;
}


bool socket_connectable(const Paths& p) {
  if (!file_exists(p.sock))
    return false;
  int fd = try_connect(p);
  if (fd < 0)
    return false;
  ::close(fd);
  return true;
}


void print_no_daemon_error(const Paths& p) {
  SmallBuf err;
  if (!p.addr_ok) {
    err.append_cstr("Error: socket path too long: ");
    err.append(p.sock, p.sock_len);
    err.push('\n');
  } else {
    err.append_cstr("Error: No daemon running (socket ");
    err.append(p.sock, p.sock_len);
    err.append_cstr(" not found).\nStart one with: portage-ng --mode daemon\n");
  }
  write_all_fd(STDERR_FILENO, err.data(), err.size());
}


// -----------------------------------------------------------------------------
//  Request encoding
// -----------------------------------------------------------------------------

//! ipcclient:tty_info(-Cols, -Rows, -IsTty)
//
// Asks the terminal on standard output for its size. That one call answers
// two questions. When it succeeds, standard output is a terminal and its size
// is known. When it fails because standard output is not a terminal, the size
// is 80 rows by 160 columns, the defaults ipclient.pl uses. For any other
// failure isatty() decides whether it is a terminal.

void tty_info(int& cols, int& rows, bool& is_tty) {
  cols = 160;
  rows = 80;
  is_tty = false;
  winsize ws{};
  if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0) {
    is_tty = true;
    if (ws.ws_col > 0 && ws.ws_row > 0) {
      cols = ws.ws_col;
      rows = ws.ws_row;
    }
  } else if (errno != ENOTTY && errno != EINVAL && errno != EBADF &&
             errno != ENODEV) {
    is_tty = ::isatty(STDOUT_FILENO) == 1;
  }
}


//! ipcclient:build_request(+Argc, +Argv, -Req)
//
// Writes the request term `request(Args, Cols, Rows, Env).` and a line feed
// into Req. Every argument and every environment value is written as a quoted
// atom.

void build_request(int argc, char** argv, SmallBuf& req) {
  int cols = 160, rows = 80;
  bool is_tty = false;
  tty_info(cols, rows, is_tty);

  req.append_cstr("request([");
  for (int i = 1; i < argc; ++i) {
    if (i > 1)
      req.push(',');
    req.append_quoted_atom(argv[i]);
  }
  req.append_cstr("], ");
  req.append_uint(static_cast<unsigned long>(cols));
  req.append_cstr(", ");
  req.append_uint(static_cast<unsigned long>(rows));
  req.append_cstr(", [");

  bool first_env = true;
  auto add_env = [&](const char* name, const char* val) {
    if (!first_env)
      req.push(',');
    first_env = false;
    req.append_quoted_atom(name);
    req.push('-');
    req.append_quoted_atom(val);
  };

  if (is_tty)
    add_env("_CLIENT_IS_TTY", "true");
  for (const char* name : kForwardedEnv) {
    if (const char* val = std::getenv(name); val)
      add_env(name, val);
  }
  req.append_cstr("]).\n");
}


bool send_all_socket(int fd, const char* data, size_t len) {
  const char* p = data;
  size_t left = len;
  while (left > 0) {
#ifdef MSG_NOSIGNAL
    ssize_t n = ::send(fd, p, left, MSG_NOSIGNAL);
#else
    ssize_t n = ::write(fd, p, left);
#endif
    if (n < 0) {
      if (errno == EINTR)
        continue;
      return false;
    }
    p += n;
    left -= static_cast<size_t>(n);
  }
  return true;
}


bool write_request(int fd, const SmallBuf& req) {
  if (send_all_socket(fd, req.data(), req.size()))
    return true;
  SmallBuf err;
  err.append_cstr("Error: write(): ");
  err.append_cstr(std::strerror(errno));
  err.push('\n');
  write_all_fd(STDERR_FILENO, err.data(), err.size());
  return false;
}


// -----------------------------------------------------------------------------
//  Copy the answer (it ends with a NUL and the line EXIT:<code>)
// -----------------------------------------------------------------------------

ssize_t read_retry(int fd, char* buf, size_t cap) {
  for (;;) {
    ssize_t n = ::read(fd, buf, cap);
    if (n < 0 && errno == EINTR)
      continue;
    return n;
  }
}


void connection_lost_error() {
  write_err_cstr(
      "Error: daemon closed the connection without an exit status.\n");
}


int parse_exit_code_span(const char* p, size_t len) {
  while (len > 0 && (p[len - 1] == '\r' || p[len - 1] == ' '))
    --len;
  if (len == 0)
    return 1;
  size_t idx = 0;
  bool neg = false;
  if (p[0] == '-' || p[0] == '+') {
    neg = (p[0] == '-');
    idx = 1;
    if (idx == len)
      return 1;
  }
  long v = 0;
  for (; idx < len; ++idx) {
    const unsigned char c = static_cast<unsigned char>(p[idx]);
    if (c < '0' || c > '9')
      return 1;
    v = v * 10 + static_cast<long>(c - '0');
    if (v > INT_MAX)
      return 1;
  }
  return neg ? static_cast<int>(-v) : static_cast<int>(v);
}


int collect_exit_code_slow(int fd, SmallBuf& acc) {
  char buf[256];
  for (;;) {
    const char* nl =
        static_cast<const char*>(std::memchr(acc.data(), '\n', acc.size()));
    if (nl)
      return parse_exit_code_span(acc.data(),
                                  static_cast<size_t>(nl - acc.data()));
    ssize_t n = read_retry(fd, buf, sizeof(buf));
    if (n < 0)
      return 1;
    if (n == 0)
      return parse_exit_code_span(acc.data(), acc.size());
    acc.append(buf, static_cast<size_t>(n));
  }
}


bool is_partial_sentinel(const char* p, size_t len) {
  return len < kSentinelLen && std::memcmp(p, kSentinel, len) == 0;
}


// Decides what a NUL means when the bytes already read do not settle it.
// `tail` holds the bytes that followed the NUL. More is read from the daemon
// for as long as `tail` could still be the beginning of `EXIT:`.
//
// Returns true when the answer is finished, with exit_code set: either the
// closing line was found or the connection ended. Returns false when the NUL
// was ordinary output. The NUL has then been written, and `tail` holds the
// bytes after it, which the caller still has to scan.
bool match_sentinel_slow(int fd, SmallBuf& tail, int& exit_code) {
  char tmp[4096];
  for (;;) {
    if (tail.size() >= kSentinelLen &&
        std::memcmp(tail.data(), kSentinel, kSentinelLen) == 0) {
      SmallBuf digits;
      digits.append(tail.data() + kSentinelLen, tail.size() - kSentinelLen);
      exit_code = collect_exit_code_slow(fd, digits);
      return true;
    }
    if (!is_partial_sentinel(tail.data(), tail.size())) {
      write_all_fd(STDOUT_FILENO, "\0", 1);
      return false;
    }
    ssize_t n = read_retry(fd, tmp, sizeof(tmp));
    if (n < 0) {
      exit_code = 1;
      return true;
    }
    if (n == 0) {
      write_all_fd(STDOUT_FILENO, "\0", 1);
      write_all_fd(STDOUT_FILENO, tail.data(), tail.size());
      connection_lost_error();
      exit_code = 1;
      return true;
    }
    tail.append(tmp, static_cast<size_t>(n));
  }
}


//! ipcclient:stream_response(+Fd)
//
// Copies the answer of the daemon from Fd to standard output and returns the
// exit code on its closing line. Returns 1 when the connection ends before
// that line.
//
// The answer is read 64 KB at a time and each block is searched for a NUL.
// A block without one, which is nearly every block, is written out in a
// single call. When the closing line is complete in the block that holds its
// NUL, which is the usual case, the exit code is read straight from the block.

int stream_response(int fd) {
  char buf[kStreamBufSize];
  SmallBuf carry;
  SmallBuf work;

  for (;;) {
    const char* p = nullptr;
    size_t len = 0;

    if (!carry.empty()) {
      // Bytes that followed a NUL which turned out to be ordinary output
      // still have to be scanned. They are moved to `work` so that `carry`
      // is free to receive what follows the next such NUL.
      work.clear();
      work.append(carry.data(), carry.size());
      carry.clear();
      p = work.data();
      len = work.size();
    } else {
      ssize_t n = read_retry(fd, buf, sizeof(buf));
      if (n < 0) {
        SmallBuf err;
        err.append_cstr("Error: read(): ");
        err.append_cstr(std::strerror(errno));
        err.push('\n');
        write_all_fd(STDERR_FILENO, err.data(), err.size());
        return 1;
      }
      if (n == 0) {
        connection_lost_error();
        return 1;
      }
      p = buf;
      len = static_cast<size_t>(n);
    }

    while (len > 0) {
      const char* nul = static_cast<const char*>(std::memchr(p, '\0', len));
      if (!nul) {
        write_all_fd(STDOUT_FILENO, p, len);
        break;
      }

      const size_t before = static_cast<size_t>(nul - p);
      if (before > 0)
        write_all_fd(STDOUT_FILENO, p, before);

      const char* after = nul + 1;
      const size_t rem = len - before - 1;

      // The usual case: the whole closing line is in this block.
      if (rem >= kSentinelLen + 2 &&
          std::memcmp(after, kSentinel, kSentinelLen) == 0) {
        const char* digits = after + kSentinelLen;
        const size_t drem = rem - kSentinelLen;
        if (const char* nl =
                static_cast<const char*>(std::memchr(digits, '\n', drem))) {
          return parse_exit_code_span(digits,
                                      static_cast<size_t>(nl - digits));
        }
      }

      SmallBuf tail;
      tail.append(after, rem);
      int exit_code = 0;
      if (match_sentinel_slow(fd, tail, exit_code))
        return exit_code;

      // The NUL was ordinary output and has been written. What followed it
      // goes round the outer loop once more. `carry` is empty at this
      // point, because it is emptied before anything is scanned.
      carry.append(tail.data(), tail.size());
      break;
    }
  }
}


// -----------------------------------------------------------------------------
//  Status / commands / autostart
// -----------------------------------------------------------------------------

//! ipcclient:wait_for_daemon(+Paths, +Retries)
//
// Returns true as soon as a daemon accepts a connection on the socket. Tries
// Retries times, 10 ms apart, and returns false when no daemon has answered by
// then. The test is a connection and not the presence of the socket file: a
// daemon that was killed leaves its socket file behind, and a file that nobody
// listens on must not be taken for a daemon that is ready.

bool wait_for_daemon(const Paths& p, int retries) {
  for (int i = 0; i < retries; ++i) {
    if (socket_connectable(p))
      return true;
    if (i + 1 < retries)
      ::usleep(10000);
  }
  return false;
}


void wait_for_socket_gone(const char* path, int retries) {
  for (int i = 0; i < retries; ++i) {
    if (!file_exists(path))
      return;
    ::usleep(10000);
  }
}


bool autostart_enabled() {
  const char* v = std::getenv("PORTAGE_NG_IPC_AUTOSTART");
  if (!v)
    return true;
  return std::strcmp(v, "0") != 0 && std::strcmp(v, "false") != 0;
}


bool find_sibling_wrapper(const char* bin_path, char* out, size_t cap) {
  if (!bin_path || !*bin_path)
    return false;
  const char* slash = std::strrchr(bin_path, '/');
  const size_t dir_len =
      slash ? static_cast<size_t>(slash - bin_path) : 1;
  const char* dir = slash ? bin_path : ".";
  constexpr char kWrapper[] = "/portage-ng-dev";
  if (dir_len + sizeof(kWrapper) > cap)
    return false;
  std::memcpy(out, dir, dir_len);
  std::memcpy(out + dir_len, kWrapper, sizeof(kWrapper));
  return ::access(out, X_OK) == 0;
}


bool resolve_daemon_wrapper(const char* argv0, char* out, size_t cap) {
  if (const char* env = std::getenv("PORTAGE_NG_DEV"); env && *env) {
    const size_t len = std::strlen(env);
    if (len + 1 <= cap && ::access(env, X_OK) == 0) {
      std::memcpy(out, env, len + 1);
      return true;
    }
  }
  if (find_sibling_wrapper(argv0, out, cap))
    return true;
  char resolved[PATH_MAX];
  if (argv0 && *argv0 && ::realpath(argv0, resolved))
    return find_sibling_wrapper(resolved, out, cap);
  return false;
}


int start_daemon_background(const char* argv0, const Paths& p) {
  char wrapper[PATH_MAX];
  if (!resolve_daemon_wrapper(argv0, wrapper, sizeof(wrapper))) {
    write_err_cstr(
        "Error: cannot locate portage-ng-dev to start the daemon.\n"
        "Set PORTAGE_NG_DEV or start one with: portage-ng --mode daemon\n");
    return 1;
  }
  write_out_cstr("Starting daemon in background...\n");
  pid_t pid = ::fork();
  if (pid < 0) {
    SmallBuf err;
    err.append_cstr("Error: fork(): ");
    err.append_cstr(std::strerror(errno));
    err.push('\n');
    write_all_fd(STDERR_FILENO, err.data(), err.size());
    return 1;
  }
  if (pid == 0) {
    int devnull = ::open("/dev/null", O_RDWR);
    if (devnull >= 0) {
      ::dup2(devnull, STDIN_FILENO);
      ::dup2(devnull, STDOUT_FILENO);
      ::dup2(devnull, STDERR_FILENO);
      if (devnull > STDERR_FILENO)
        ::close(devnull);
    }
    ::execl(wrapper, wrapper, "--mode", "daemon", "--background",
            static_cast<char*>(nullptr));
    _exit(127);
  }
  int status = 0;
  while (::waitpid(pid, &status, 0) < 0) {
    if (errno != EINTR) {
      SmallBuf err;
      err.append_cstr("Error: waitpid(): ");
      err.append_cstr(std::strerror(errno));
      err.push('\n');
      write_all_fd(STDERR_FILENO, err.data(), err.size());
      return 1;
    }
  }
  if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
    SmallBuf err;
    err.append_cstr("Error: failed to start daemon (status ");
    err.append_uint(static_cast<unsigned long>(status));
    err.append_cstr(").\n");
    write_all_fd(STDERR_FILENO, err.data(), err.size());
    return 1;
  }
  if (wait_for_daemon(p, 6000)) {
    write_out_cstr("Daemon ready.\n");
    return 0;
  }
  write_err_cstr("Warning: daemon may not have started.\n");
  return 0;
}


size_t read_pid_file(const char* pid_path, char* buf, size_t cap) {
  int fd = ::open(pid_path, O_RDONLY);
  if (fd < 0)
    return 0;
  ssize_t n = read_retry(fd, buf, cap - 1);
  ::close(fd);
  if (n <= 0)
    return 0;
  size_t len = static_cast<size_t>(n);
  while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r' ||
                     buf[len - 1] == ' ' || buf[len - 1] == '\t'))
    --len;
  buf[len] = '\0';
  return len;
}


int cmd_status(const Paths& p) {
  if (!socket_connectable(p)) {
    write_out_cstr("No daemon running.\n");
    return 1;
  }
  char pid[64];
  const size_t pid_len = read_pid_file(p.pid, pid, sizeof(pid));
  SmallBuf out;
  if (pid_len > 0) {
    out.append_cstr("Daemon running (PID ");
    out.append(pid, pid_len);
    out.append_cstr(", socket ");
    out.append(p.sock, p.sock_len);
    out.append_cstr(")\n");
  } else {
    out.append_cstr("Daemon socket exists (");
    out.append(p.sock, p.sock_len);
    out.append_cstr(") but no PID file.\n");
  }
  write_all_fd(STDOUT_FILENO, out.data(), out.size());
  return 0;
}


int cmd_halt(const Paths& p) {
  int fd = try_connect(p);
  if (fd < 0) {
    write_err_cstr("No daemon running.\n");
    return 0;
  }
  if (!send_all_socket(fd, "shutdown.\n", 10)) {
    ::close(fd);
    return 1;
  }
  char drain[256];
  while (read_retry(fd, drain, sizeof(drain)) > 0) {
  }
  ::close(fd);
  write_out_cstr("Daemon stopped.\n");
  return 0;
}


int cmd_relaunch(const char* argv0, const Paths& p) {
  cmd_halt(p);
  wait_for_socket_gone(p.sock, 600);
  return start_daemon_background(argv0, p);
}


int send_command(const char* argv0, const Paths& p, const char* cmd) {
  if (std::strcmp(cmd, "halt") == 0)
    return cmd_halt(p);
  if (std::strcmp(cmd, "relaunch") == 0)
    return cmd_relaunch(argv0, p);
  SmallBuf err;
  err.append_cstr("Unknown command: ");
  err.append_cstr(cmd);
  err.append_cstr(". Use halt or relaunch.\n");
  write_all_fd(STDERR_FILENO, err.data(), err.size());
  return 1;
}


void usage(const char* argv0, const Paths& p) {
  SmallBuf err;
  err.append_cstr("Usage:\n  ");
  err.append_cstr(argv0);
  err.append_cstr(" --mode ipc --pretend <pkg>\n  ");
  err.append_cstr(argv0);
  err.append_cstr(" --status\n  ");
  err.append_cstr(argv0);
  err.append_cstr(" --cmd halt|relaunch\n\nSocket: ");
  err.append(p.sock, p.sock_len);
  err.push('\n');
  write_all_fd(STDERR_FILENO, err.data(), err.size());
}


// -----------------------------------------------------------------------------
//  Flags the client handles itself
// -----------------------------------------------------------------------------

// Looks through the arguments once for the flags the client acts on itself.
// The other arguments are not interpreted here. They are sent to the daemon
// as they are.

struct CliFlags {
  bool shell = false;
  bool help = false;
  bool status = false;
  bool missing_cmd = false;
  const char* cmd = nullptr;
};


CliFlags scan_cli(int argc, char** argv) {
  CliFlags f;
  for (int i = 1; i < argc; ++i) {
    const char* a = argv[i];
    if (a[0] != '-')
      continue;
    if (std::strcmp(a, "--shell") == 0) {
      f.shell = true;
    } else if (std::strcmp(a, "-h") == 0 || std::strcmp(a, "--help") == 0) {
      f.help = true;
    } else if (std::strcmp(a, "--status") == 0) {
      f.status = true;
    } else if (std::strcmp(a, "--cmd") == 0) {
      if (i + 1 < argc)
        f.cmd = argv[++i];
      else
        f.missing_cmd = true;
    } else if (std::strncmp(a, "--cmd=", 6) == 0) {
      if (a[6] != '\0')
        f.cmd = a + 6;
      else
        f.missing_cmd = true;
    }
  }
  return f;
}

} // namespace


//! ipcclient:main(+Argc, +Argv)
//
// Handles --status, --cmd, --shell and --help itself. Anything else is sent
// to the daemon as one request. The connection is simply tried, without
// looking at the socket file first. Only when nobody answers, and autostart
// is enabled, is a daemon started and the connection tried a second time.

int main(int argc, char** argv) {
  Paths paths{};
  if (!init_paths(paths)) {
    write_err_cstr("Error: runtime directory path exceeds PATH_MAX.\n");
    return 1;
  }

  const char* argv0 = (argc > 0 && argv[0]) ? argv[0] : "ipcclient";
  if (argc < 2) {
    usage(argv0, paths);
    return 1;
  }

  const CliFlags cli = scan_cli(argc, argv);
  if (cli.shell) {
    write_err_cstr("Error: --shell is not supported in ipc mode. "
                   "Use --mode standalone --shell instead.\n");
    return 1;
  }
  if (cli.help) {
    usage(argv0, paths);
    return 0;
  }
  if (cli.status)
    return cmd_status(paths);
  if (cli.cmd)
    return send_command(argv0, paths, cli.cmd);
  if (cli.missing_cmd) {
    write_err_cstr("Error: --cmd requires an argument\n");
    return 1;
  }

  int fd = try_connect(paths);
  if (fd < 0) {
    if (!paths.addr_ok || !autostart_enabled()) {
      print_no_daemon_error(paths);
      return 1;
    }
    if (start_daemon_background(argv0, paths) != 0)
      return 1;
    fd = try_connect(paths);
    if (fd < 0) {
      print_no_daemon_error(paths);
      return 1;
    }
  }

  SmallBuf req;
  build_request(argc, argv, req);
  if (!write_request(fd, req)) {
    ::close(fd);
    return 1;
  }

  const int code = stream_response(fd);
  ::close(fd);
  return code;
}