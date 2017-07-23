/**@file uart.c
 * @brief This is a program for transferring data via the UART to the target
 * board, it is currently Linux only (not tested on other Unixen). It sends
 * a byte via a UART (115200 baud, 8 bits, 1 stop bit).
 *
 * @author Richard James Howe
 * @copyright Richard James Howe (c) 2017
 * @license MIT
 */

#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>

static int open_tty(const char * port)
{
	int fd;
	errno = 0;
	fd = open(port, O_RDWR | O_NOCTTY);
	if (fd == -1) {
		fprintf(stderr, "%s unable to open '%s': %s\n", __func__, port, strerror(errno));
		exit(EXIT_FAILURE);
	}
	return fd;
}

static void *stdin_to_uart(void *x)
{
	int fd = *(int*)x;
	int c = 0;
	unsigned char c1 = 0;
	while(EOF != (c = fgetc(stdin))) {
		c1 = c;
		errno = 0;
		if (write(fd, &c1, 1) != 1) {
			fprintf(stderr, "write error:%s\n", strerror(errno));
			return NULL;
		}
		/** @bug Writing too fast causes problems! The H2 CPU
		 * probably cannot process things fast enough. */
		tcflush(fd,TCIOFLUSH);
		usleep(1000);

	}
	exit(EXIT_SUCCESS);
	return NULL;
}

static void *uart_to_stdout(void *x)
{
	int fd = *(int*)x;
	unsigned char c[128] = {0};
	int r = 0;

	for(;;) {
		if((r = read(fd, c, sizeof(c) - 1)) >=0)
			write(1, c, r);
	}
	return NULL;
}

int main(int argc, char **argv)
{
	int fd = -1;
	int ch;
	const char *port = "/dev/ttyUSB0";
	struct termios options;
	pthread_t p1, p2;

	if (argc == 2) {
		port = argv[1];
	} else if (argc != 1) {
		fprintf(stderr, "usage: %s /dev/ttyUSBX <file\n", argv[0]);
		return -1;
	}
	fd = open_tty(port);

	errno = 0;
	if (tcgetattr(fd, &options) < 0) {
		fprintf(stderr, "failed to get terminal options on fd %d: %s\n", fd, strerror(errno));
		return -1;
	}

	cfsetispeed(&options, B115200);
	cfsetospeed(&options, B115200);

	cfmakeraw(&options);
	options.c_cflag |= (CLOCAL | CREAD); /* Enable the receiver and set local mode */
	options.c_cflag &= ~CSTOPB;	     /* 1 stopbit */
	options.c_cflag &= ~CRTSCTS;         /* Disable hardware flow control */

#ifndef OLD

	// options.c_cc[VMIN]  = 0;
	// options.c_cc[VTIME] = 1;             /* Timeout read after 1 second */

	errno = 0;
	if (tcsetattr(fd, TCSANOW, &options) < 0) {
		fprintf(stderr, "failed to set terminal options on fd %d: %s\n", fd, strerror(errno));
		exit(EXIT_FAILURE);
	}

	errno = 0;
	if(pthread_create(&p1, NULL, uart_to_stdout, &fd)) {
		fprintf(stderr, "failed to create thread 1: %s\n", strerror(errno));
		exit(EXIT_FAILURE);
	}

	errno = 0;
	if(pthread_create(&p2, NULL, stdin_to_uart, &fd)) {
		fprintf(stderr, "failed to create thread 2: %s\n", strerror(errno));
		exit(EXIT_FAILURE);
	}

	if(pthread_join(p2, NULL)) {
		fprintf(stderr, "Error joining thread\n");
		return -2;
	}

	close(fd);
	return 0;
#else
	options.c_cc[VMIN]  = 0;
	options.c_cc[VTIME] = 1;             /* Timeout read after 1 second */

	errno = 0;
	if (tcsetattr(fd, TCSANOW, &options) < 0) {
		fprintf(stderr, "failed to set terminal options on fd %d: %s\n", fd, strerror(errno));
		exit(EXIT_FAILURE);
	}

	while (EOF != (ch = fgetc(stdin))) {
		char c1 = ch, c2 = 0;
		int r = 0;
 again:
		errno = 0;
		if (write(fd, &c1, 1) != 1) {
			fprintf(stderr, "write error:%s\n", strerror(errno));
			return -1;
		}
		tcflush(fd,TCIOFLUSH);
		usleep(100);
		errno = 0;
		r = read(fd, &c2, 1);
		if (r == 0) {
			/*fprintf(stderr,"retransmitting...\n"); */
			goto again;
		} else if(r < 0) {
			fprintf(stderr, "read error:%s\n", strerror(errno));
			return -1;
		}

		if (c1 != c2)
			fprintf(stderr, "error: transmitted '%d' got back '%d'\n", c1, c2);

		write(2, &c1, 1);
	}

	close(fd);
	return 0;

#endif
}

