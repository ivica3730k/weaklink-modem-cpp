#include "weaklink/ptt.hpp"

#include <cerrno>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

#include "weaklink/constants.hpp"
#include "weaklink/exceptions.hpp"
#include "weaklink/log.hpp"

namespace weaklink::ptt {
namespace {

Logger& log() {
  static Logger logger("weaklink.ptt");
  return logger;
}

#if defined(_WIN32)
using SocketHandle = SOCKET;
constexpr SocketHandle kInvalidSocket = INVALID_SOCKET;
void close_socket(int handle) { ::closesocket(static_cast<SocketHandle>(handle)); }

/// Winsock needs process-wide initialisation before any socket call.
struct WinsockSession {
  WinsockSession() {
    WSADATA data;
    WSAStartup(MAKEWORD(2, 2), &data);
  }
  ~WinsockSession() { WSACleanup(); }
};
#else
void close_socket(int handle) { ::close(handle); }
#endif

int connect_to(const std::string& host, int port) {
#if defined(_WIN32)
  static WinsockSession winsock;
#endif
  addrinfo hints{};
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;

  addrinfo* results = nullptr;
  const std::string service = std::to_string(port);
  if (::getaddrinfo(host.c_str(), service.c_str(), &hints, &results) != 0 || results == nullptr) {
    throw PTTError("rigctld connect " + host + ":" + service + " failed: host not found");
  }

  int handle = -1;
  for (addrinfo* entry = results; entry != nullptr; entry = entry->ai_next) {
    const int candidate =
        static_cast<int>(::socket(entry->ai_family, entry->ai_socktype, entry->ai_protocol));
    if (candidate < 0) {
      continue;
    }
    if (::connect(candidate, entry->ai_addr, static_cast<socklen_t>(entry->ai_addrlen)) == 0) {
      handle = candidate;
      break;
    }
    close_socket(candidate);
  }
  ::freeaddrinfo(results);

  if (handle < 0) {
    throw PTTError("rigctld connect " + host + ":" + service + " failed: " +
                   std::strerror(errno));
  }
  return handle;
}

// A dropped rigctld connection must surface as a PTTError. Without this the
// send raises SIGPIPE, and the CLI only handles SIGINT and SIGTERM, so a broken
// control link would take the whole process down mid-transmission.
#if defined(MSG_NOSIGNAL)
constexpr int kSendFlags = MSG_NOSIGNAL;
#else
constexpr int kSendFlags = 0;
#endif

/// Platforms without MSG_NOSIGNAL (macOS, the BSDs) suppress it per socket.
void suppress_sigpipe(int handle) {
#if !defined(MSG_NOSIGNAL) && defined(SO_NOSIGPIPE)
  int on = 1;
  ::setsockopt(handle, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
#else
  (void)handle;
#endif
}

void send_command(int handle, const char* command) {
  const std::size_t length = std::strlen(command);
  std::size_t sent = 0;
  while (sent < length) {
#if defined(_WIN32)
    const int written = ::send(static_cast<SocketHandle>(handle), command + sent,
                               static_cast<int>(length - sent), kSendFlags);
#else
    const ssize_t written = ::send(handle, command + sent, length - sent, kSendFlags);
#endif
    if (written <= 0) {
      throw PTTError(std::string("rigctld ") + command + " failed: " + std::strerror(errno));
    }
    sent += static_cast<std::size_t>(written);
  }
}

/// rigctld answers every command with ``RPRT <code>``. Sending the bytes only
/// means they left the socket: a refused key-up still reports RPRT != 0, and
/// transmitting over an unkeyed radio loses the whole message silently.
void check_reply(int handle, const char* command) {
  char reply[64] = {0};
  std::size_t filled = 0;
  while (filled + 1 < sizeof(reply)) {
#if defined(_WIN32)
    const int got = ::recv(static_cast<SocketHandle>(handle), reply + filled,
                           static_cast<int>(sizeof(reply) - 1 - filled), 0);
#else
    const ssize_t got = ::recv(handle, reply + filled, sizeof(reply) - 1 - filled, 0);
#endif
    if (got <= 0) {
      throw PTTError(std::string("rigctld ") + command + ": no reply (" +
                     std::strerror(errno) + ")");
    }
    filled += static_cast<std::size_t>(got);
    if (std::memchr(reply, '\n', filled) != nullptr) {
      break;
    }
  }
  const std::string text(reply, filled);
  const std::size_t marker = text.find("RPRT");
  if (marker == std::string::npos) {
    throw PTTError(std::string("rigctld ") + command + ": unexpected reply '" + text + "'");
  }
  const int code = std::atoi(text.c_str() + marker + 4);
  if (code != 0) {
    throw PTTError(std::string("rigctld ") + command + " rejected: RPRT " +
                   std::to_string(code));
  }
}

/// Bound the reply wait: a rigctld that accepts the connection and then goes
/// quiet would otherwise block the transmission forever.
void set_reply_timeout(int handle, double seconds) {
#if defined(_WIN32)
  auto milliseconds = static_cast<DWORD>(seconds * 1000.0);
  ::setsockopt(static_cast<SocketHandle>(handle), SOL_SOCKET, SO_RCVTIMEO,
               reinterpret_cast<const char*>(&milliseconds), sizeof(milliseconds));
#else
  timeval timeout{};
  timeout.tv_sec = static_cast<time_t>(seconds);
  timeout.tv_usec = static_cast<suseconds_t>((seconds - static_cast<double>(timeout.tv_sec)) *
                                             1e6);
  ::setsockopt(handle, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
#endif
}

void sleep_seconds(double seconds) {
  std::this_thread::sleep_for(std::chrono::duration<double>(seconds));
}

}  // namespace

std::pair<std::string, int> parse_endpoint(const std::string& spec) {
  const std::size_t colon = spec.find(':');
  if (colon == std::string::npos) {
    return {spec.empty() ? "localhost" : spec, kHamlibDefaultPort};
  }
  std::string host = spec.substr(0, colon);
  const std::string port_text = spec.substr(colon + 1);
  if (host.empty()) {
    host = "localhost";
  }
  if (port_text.empty()) {
    return {host, kHamlibDefaultPort};
  }
  try {
    return {host, std::stoi(port_text)};
  } catch (const std::exception&) {
    throw ConfigError("invalid --hamlib-ptt port '" + port_text + "'");
  }
}

HamlibPtt::HamlibPtt(const std::string& spec) {
  if (spec.empty()) {
    return;
  }
  const auto endpoint = parse_endpoint(spec);
  log().debug("hamlib PTT: connecting to ", endpoint.first, ":", endpoint.second);
  socket_ = connect_to(endpoint.first, endpoint.second);
  suppress_sigpipe(socket_);
  set_reply_timeout(socket_, kHamlibReplyTimeoutSeconds);
  try {
    send_command(socket_, "T 1\n");
    check_reply(socket_, "T 1");
  } catch (...) {
    close_socket(socket_);
    socket_ = -1;
    throw;
  }
  // Radios need a gap between key-up and the first sample or the leading pilot
  // is clipped by relay and AGC settling.
  log().debug("hamlib PTT: keyed, waiting ", kHamlibPttLeadSeconds * 1000, " ms");
  sleep_seconds(kHamlibPttLeadSeconds);
}

HamlibPtt::~HamlibPtt() {
  if (socket_ < 0) {
    return;
  }
  // Symmetric tail: hold past the last sample so the trailing pilot makes it
  // out before the relay drops.
  log().debug("hamlib PTT: holding tail ", kHamlibPttTailSeconds * 1000, " ms");
  sleep_seconds(kHamlibPttTailSeconds);
  try {
    send_command(socket_, "T 0\n");
    check_reply(socket_, "T 0");
    log().debug("hamlib PTT: released");
  } catch (const std::exception& error) {
    log().warning("hamlib PTT: release failed: ", error.what());
  }
  close_socket(socket_);
  socket_ = -1;
}

}  // namespace weaklink::ptt
