// SPDX-License-Identifier: GPL-2.0
/*
 * Race test for the v4l2-subdev NULL dereferences on unbind.
 *
 * Runs as /init of an initramfs inside QEMU. While one thread unbinds and
 * rebinds vimc through sysfs, other threads:
 *
 *   - open and close every /dev/v4l-subdevN   (subdev_open(), patch 1/2)
 *   - keep a handle open and loop VIDIOC_G_EXT_CTRLS on it
 *                                             (EXT_CTRLS ioctls, patch 2/2)
 *
 * The kernel log goes to the serial console, which the host saves: the
 * host counts oopses and KASAN reports there, not this program.
 *
 * Build: gcc -O2 -static -pthread -o init race.c
 */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <time.h>
#include <limits.h>
#include <unistd.h>
#include <linux/videodev2.h>

#define VIMC_DRV	"/sys/bus/platform/drivers/vimc"
#define VIMC_DEV	"vimc.0"
#define MAX_NODES	32
#define N_OPENERS	16
#define N_IOCTLERS	4

static atomic_int stop;
static atomic_long n_open_ok, n_open_err, n_ioctl_ok, n_ioctl_err, n_cycles;

static void msleep(unsigned int ms)
{
	struct timespec ts = { ms / 1000, (ms % 1000) * 1000000L };

	nanosleep(&ts, NULL);
}

static int write_str(const char *path, const char *s)
{
	int fd = open(path, O_WRONLY);
	int ret = 0;

	if (fd < 0)
		return -errno;
	if (write(fd, s, strlen(s)) < 0)
		ret = -errno;
	close(fd);
	return ret;
}

/* Nodes come and go with the unbind loop, so look them up every time. */
static int pick_node(char *buf, size_t len, unsigned int seed)
{
	char names[MAX_NODES][NAME_MAX + 1];
	struct dirent *de;
	int n = 0;
	DIR *d;

	d = opendir("/dev");
	if (!d)
		return -1;
	while ((de = readdir(d)) && n < MAX_NODES)
		if (!strncmp(de->d_name, "v4l-subdev", 10))
			snprintf(names[n++], sizeof(names[0]), "%s", de->d_name);
	closedir(d);
	if (!n)
		return -1;
	snprintf(buf, len, "/dev/%s", names[seed % n]);
	return 0;
}

static void *opener(void *arg)
{
	unsigned int seed = (unsigned long)arg;
	char path[PATH_MAX];

	while (!stop) {
		int fd;

		if (pick_node(path, sizeof(path), seed++))
			continue;
		fd = open(path, O_RDWR);
		if (fd < 0) {
			n_open_err++;
			continue;
		}
		n_open_ok++;
		close(fd);
	}
	return NULL;
}

static void *ioctler(void *arg)
{
	unsigned int seed = (unsigned long)arg;
	char path[PATH_MAX];

	while (!stop) {
		struct v4l2_ext_controls ctrls;
		int fd, i;

		if (pick_node(path, sizeof(path), seed++))
			continue;
		fd = open(path, O_RDWR);
		if (fd < 0)
			continue;
		/* Keep the handle across an unbind and keep asking. */
		for (i = 0; i < 2000 && !stop; i++) {
			memset(&ctrls, 0, sizeof(ctrls));
			ctrls.which = V4L2_CTRL_WHICH_CUR_VAL;
			if (ioctl(fd, VIDIOC_G_EXT_CTRLS, &ctrls) < 0) {
				n_ioctl_err++;
				if (errno == ENODEV)
					break;
			} else {
				n_ioctl_ok++;
			}
		}
		close(fd);
	}
	return NULL;
}

static void *unbinder(void *arg)
{
	unsigned int period_ms = (unsigned long)arg;

	while (!stop) {
		write_str(VIMC_DRV "/unbind", VIMC_DEV);
		msleep(period_ms);
		write_str(VIMC_DRV "/bind", VIMC_DEV);
		msleep(period_ms);
		n_cycles++;
	}
	return NULL;
}

static void run_phase(unsigned int period_ms, unsigned int seconds)
{
	pthread_t t[N_OPENERS + N_IOCTLERS + 1];
	unsigned long i, n = 0;

	stop = 0;
	n_open_ok = n_open_err = n_ioctl_ok = n_ioctl_err = n_cycles = 0;

	for (i = 0; i < N_OPENERS; i++)
		pthread_create(&t[n++], NULL, opener, (void *)i);
	for (i = 0; i < N_IOCTLERS; i++)
		pthread_create(&t[n++], NULL, ioctler, (void *)(i * 7));
	pthread_create(&t[n++], NULL, unbinder, (void *)(unsigned long)period_ms);

	sleep(seconds);
	stop = 1;
	for (i = 0; i < n; i++)
		pthread_join(t[i], NULL);

	/* Leave vimc bound for the next phase. */
	write_str(VIMC_DRV "/bind", VIMC_DEV);

	printf("RACE-PHASE period=%ums seconds=%u cycles=%ld open_ok=%ld open_err=%ld ioctl_ok=%ld ioctl_err=%ld\n",
	       period_ms, seconds, (long)n_cycles, (long)n_open_ok,
	       (long)n_open_err, (long)n_ioctl_ok, (long)n_ioctl_err);
	fflush(stdout);
}

int main(void)
{
	unsigned int seconds = 60;
	struct stat st;

	mount("proc", "/proc", "proc", 0, NULL);
	mount("sysfs", "/sys", "sysfs", 0, NULL);
	mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);

	if (stat(VIMC_DRV "/" VIMC_DEV, &st)) {
		printf("RACE-ERROR vimc.0 not bound at start\n");
		goto out;
	}

	printf("RACE-START\n");
	fflush(stdout);
	run_phase(1, seconds);
	run_phase(30, seconds);
	printf("RACE-END\n");

out:
	fflush(stdout);
	sync();
	reboot(RB_POWER_OFF);
	return 0;
}
