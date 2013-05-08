#include "serial.h"

#include "debug.h"
#include "str.h"

#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <fcntl.h>
#include <termios.h>
#include <sys/ioctl.h>

#if defined(__APPLE__)
#include <IOKit/serial/ioss.h>
#elif defined(__linux__)
#include <linux/serial.h>
#endif

int serial_open(char *path)
{
  int fd = open(path, O_RDWR | O_NOCTTY | O_NDELAY);
  if (fd == -1) EXIT_ON_POSIX_ERROR("cannot open port", 2);
  return fd;
}

void serial_setup(int fd, int baudrate, char *charopts)
{
  if (str_diff(charopts, "8N1")) {
    eprintf ("error: unsupported character options\n");
    exit(1);
  }

  struct termios options;

  tcgetattr(fd, &options);

#if defined(__APPLE__)
  // will be set later
#elif defined(__linux__)
  int baudopt = B0;
  switch (baudrate) {
    case 50:     baudopt = B50;     break;
    case 75:     baudopt = B75;     break;
    case 110:    baudopt = B110;    break;
    case 134:    baudopt = B134;    break;
    case 150:    baudopt = B150;    break;
    case 200:    baudopt = B200;    break;
    case 300:    baudopt = B300;    break;
    case 600:    baudopt = B600;    break;
    case 1200:   baudopt = B1200;   break;
    case 1800:   baudopt = B1800;   break;
    case 2400:   baudopt = B2400;   break;
    case 4800:   baudopt = B4800;   break;
    case 9600:   baudopt = B9600;   break;
    case 19200:  baudopt = B19200;  break;
    case 38400:  baudopt = B38400;  break;
    case 57600:  baudopt = B57600;  break;
    case 115200: baudopt = B115200; break;
    case 230400: baudopt = B230400; break;
  }
  if (baudopt == B0) {
    cfsetispeed(&options, B38400);
    cfsetospeed(&options, B38400);
  } else {
    cfsetispeed(&options, baudopt);
    cfsetospeed(&options, baudopt);
  }
#else
#error "custom baudrate setting: unknown platform"
#endif

  options.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);

  options.c_iflag |= IGNPAR;

  options.c_iflag &= ~(IXON | IXOFF | IXANY);

  options.c_oflag &= ~OPOST;

  cfmakeraw(&options);

  options.c_cflag &= ~CSIZE;
  options.c_cflag |= CS8;
  options.c_cflag &= ~PARENB;
  options.c_cflag |= CSTOPB;

  options.c_cflag &= ~CRTSCTS;

  if (tcsetattr(fd, TCSANOW, &options) == -1) EXIT_ON_POSIX_ERROR("cannot set port parameters", 2);

#if defined(__APPLE__)
  if (ioctl(fd, IOSSIOSPEED, &baudrate) == -1)
    EXIT_ON_POSIX_ERROR("custom baudrate ioctl (IOSSIOSPEED) failed", 2);
#elif defined(__linux__)
  if (baudopt == B0) {
    struct serial_struct sstruct;
    if(ioctl(fd, TIOCGSERIAL, &sstruct) < 0) EXIT_ON_POSIX_ERROR("custom baudrate ioctl (TIOCGSERIAL) failed", 2);
    sstruct.custom_divisor = sstruct.baud_base / baudrate;
    sstruct.flags &= ~ASYNC_SPD_MASK;
    sstruct.flags |= ASYNC_SPD_CUST;
    if(ioctl(fd, TIOCSSERIAL, &sstruct) < 0) EXIT_ON_POSIX_ERROR("custom baudrate ioctl (TIOCSSERIAL) failed", 2);
  }
#endif
}
