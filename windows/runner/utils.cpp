#include "utils.h"

#include <array>
#include <fcntl.h>
#include <flutter_windows.h>
#include <io.h>
#include <mutex>
#include <stdio.h>
#include <string_view>
#include <thread>
#include <windows.h>

#include <iostream>

namespace {

bool IsValidHandle(HANDLE handle) {
  return handle != nullptr && handle != INVALID_HANDLE_VALUE;
}

bool ShouldSuppressStderrLine(std::string_view line) {
  return line.find("accessibility_bridge.cc") != std::string_view::npos &&
         line.find("Failed to update ui::AXTree") !=
             std::string_view::npos;
}

void ForwardStderrChunk(HANDLE handle, const std::string& chunk) {
  if (!IsValidHandle(handle) || chunk.empty()) {
    return;
  }
  DWORD written = 0;
  WriteFile(handle, chunk.data(), static_cast<DWORD>(chunk.size()), &written,
            nullptr);
}

void PumpFilteredStderr(HANDLE read_pipe, HANDLE original_stderr) {
  std::array<char, 4096> buffer{};
  std::string pending;
  DWORD bytes_read = 0;
  while (ReadFile(read_pipe, buffer.data(), static_cast<DWORD>(buffer.size()),
                  &bytes_read, nullptr) &&
         bytes_read > 0) {
    pending.append(buffer.data(), bytes_read);
    size_t newline = pending.find('\n');
    while (newline != std::string::npos) {
      const std::string line = pending.substr(0, newline + 1);
      if (!ShouldSuppressStderrLine(line)) {
        ForwardStderrChunk(original_stderr, line);
      }
      pending.erase(0, newline + 1);
      newline = pending.find('\n');
    }
  }

  if (!pending.empty() && !ShouldSuppressStderrLine(pending)) {
    ForwardStderrChunk(original_stderr, pending);
  }

  if (IsValidHandle(read_pipe)) {
    CloseHandle(read_pipe);
  }
  if (IsValidHandle(original_stderr)) {
    CloseHandle(original_stderr);
  }
}

}  // namespace

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

void InstallStderrFilter() {
  static std::once_flag once;
  std::call_once(once, []() {
    const HANDLE stderr_handle = GetStdHandle(STD_ERROR_HANDLE);
    if (!IsValidHandle(stderr_handle)) {
      return;
    }

    HANDLE original_stderr = INVALID_HANDLE_VALUE;
    if (!DuplicateHandle(GetCurrentProcess(), stderr_handle,
                         GetCurrentProcess(), &original_stderr, 0, FALSE,
                         DUPLICATE_SAME_ACCESS)) {
      return;
    }

    SECURITY_ATTRIBUTES attributes = {};
    attributes.nLength = sizeof(attributes);
    attributes.bInheritHandle = TRUE;

    HANDLE read_pipe = INVALID_HANDLE_VALUE;
    HANDLE write_pipe = INVALID_HANDLE_VALUE;
    if (!CreatePipe(&read_pipe, &write_pipe, &attributes, 0)) {
      CloseHandle(original_stderr);
      return;
    }
    SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0);

    const int pipe_fd =
        _open_osfhandle(reinterpret_cast<intptr_t>(write_pipe), _O_TEXT);
    if (pipe_fd == -1) {
      CloseHandle(read_pipe);
      CloseHandle(write_pipe);
      CloseHandle(original_stderr);
      return;
    }

    if (_dup2(pipe_fd, _fileno(stderr)) != 0) {
      _close(pipe_fd);
      CloseHandle(read_pipe);
      CloseHandle(original_stderr);
      return;
    }
    _close(pipe_fd);

    setvbuf(stderr, nullptr, _IONBF, 0);
    std::ios::sync_with_stdio();

    const intptr_t filtered_stderr = _get_osfhandle(_fileno(stderr));
    if (filtered_stderr != -1) {
      SetStdHandle(STD_ERROR_HANDLE,
                   reinterpret_cast<HANDLE>(filtered_stderr));
    }
    FlutterDesktopResyncOutputStreams();

    std::thread(PumpFilteredStderr, read_pipe, original_stderr).detach();
  });
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}
