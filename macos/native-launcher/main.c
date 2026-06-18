#include <mach-o/dyld.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int executable_dir(char *buffer, size_t buffer_size) {
  char path[PATH_MAX];
  uint32_t size = sizeof(path);

  if (_NSGetExecutablePath(path, &size) != 0) {
    return -1;
  }

  char resolved[PATH_MAX];
  const char *source = realpath(path, resolved) ? resolved : path;
  const char *slash = strrchr(source, '/');
  if (!slash) {
    return -1;
  }

  size_t length = (size_t)(slash - source);
  if (length + 1 > buffer_size) {
    return -1;
  }

  memcpy(buffer, source, length);
  buffer[length] = '\0';
  return 0;
}

int main(int argc, char *argv[]) {
  char macos_dir[PATH_MAX];
  if (executable_dir(macos_dir, sizeof(macos_dir)) != 0) {
    fprintf(stderr, "Codex Launcher: failed to resolve app executable path.\n");
    return 1;
  }

  char script_path[PATH_MAX];
  int written = snprintf(
      script_path,
      sizeof(script_path),
      "%s/../Resources/launcher.zsh",
      macos_dir);
  if (written < 0 || (size_t)written >= sizeof(script_path)) {
    fprintf(stderr, "Codex Launcher: launcher script path is too long.\n");
    return 1;
  }

  char **exec_argv = calloc((size_t)argc + 2, sizeof(char *));
  if (!exec_argv) {
    fprintf(stderr, "Codex Launcher: failed to allocate argv.\n");
    return 1;
  }

  exec_argv[0] = "/bin/zsh";
  exec_argv[1] = script_path;
  for (int i = 1; i < argc; i++) {
    exec_argv[i + 1] = argv[i];
  }
  exec_argv[argc + 1] = NULL;

  execv("/bin/zsh", exec_argv);
  perror("Codex Launcher: failed to run /bin/zsh");
  free(exec_argv);
  return 1;
}
