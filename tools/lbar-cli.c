/* lbar-cli — send a command to the running lbar instance
 * usage: lbar-cli toggle_launcher | lbar-cli toggle launcher */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

int main(int argc, char **argv) {
  const char *rt = getenv("XDG_RUNTIME_DIR");
  char path[128];
  if (!rt || !rt[0])
    rt = "/tmp";
  snprintf(path, sizeof(path), "%s/lbar.sock", rt);

  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0)
    return 1;
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  size_t plen = strlen(path);
  if (plen >= sizeof(addr.sun_path))
    plen = sizeof(addr.sun_path) - 1;
  memcpy(addr.sun_path, path, plen);
  addr.sun_path[plen] = 0;
  if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
    fprintf(stderr, "lbar-cli: cannot connect to %s (is lbar running?)\n",
            path);
    close(fd);
    return 1;
  }

  char msg[256];
  int off = 0;
  for (int i = 1; i < argc && off < (int)sizeof(msg) - 2; i++) {
    if (i > 1)
      msg[off++] = ' ';
    int len = snprintf(msg + off, sizeof(msg) - off, "%s", argv[i]);
    if (len < 0)
      break;
    off += len;
  }
  if (off <= 0) {
    fprintf(stderr, "usage: lbar-cli <action> [args...]\n");
    close(fd);
    return 1;
  }
  msg[off++] = '\n';
  if (write(fd, msg, off) < 0)
    return 1;
  close(fd);
  return 0;
}
