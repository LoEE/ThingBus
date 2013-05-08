#include "extproc-slave.h"

#include "debug.h"

#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <arpa/inet.h>

int connect_localhost (char *ioaddr)
{
  int sock;
  struct sockaddr_in name;
  long port = strtol(ioaddr, NULL, 10);

  if (port < 0 || port > 65535)
    return 0;

  sock = socket (AF_INET, SOCK_STREAM, 0);
  if(!sock) EXIT_ON_POSIX_ERROR("failed to create a TCP socket", 2);

  name.sin_family = AF_INET;
  name.sin_port = htons(port);
  name.sin_addr.s_addr = inet_addr("127.0.0.1");
  if(connect (sock, (struct sockaddr *) &name, sizeof (name)) < 0)
    EXIT_ON_POSIX_ERROR("failed to connect to localhost", 2);

  // TODO: handle tokens when ioaddr is "<port>-<token>"

  return sock;
}
