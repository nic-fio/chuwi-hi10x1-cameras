// SPDX-License-Identifier: GPL-2.0
/*
 * Race test for the v4l2-subdev NULL dereferences on unbind.
 *
 * Runs as /init of an initramfs inside QEMU. While one thread unbinds and
 * rebinds vimc through sysfs, other threads exercise one path at a time:
 *
 *   open  phases: open and close /dev/v4l-subdevN     (subdev_open(), 1/2)
 *   ioctl phases: keep a handle open across unbinds and loop
 *                 VIDIOC_G_EXT_CTRLS on it              (EXT_CTRLS, 2/2)
 *
 * Separate phases keep the attribution of a crash unambiguous, and keep
 * the ioctl threads from being starved when the open threads die.
 *
 * Each oops kills the thread that hit it, not PID 1, so a crash count is
 * "threads killed", not "race hits". The kernel log goes to the serial
 * console, which the host saves and counts; this program only reports
 * whether each phase really exercised the path (RACE-PHASE lines), so
 * that a hung or idle run cannot pass for a clean one.
 *
 * Build: gcc -O2 -Wall -static -pthread -o init race.c
 */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
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
#include <unistd.h>
#include <linux/videodev2.h>

#define VIMC_DRV	"/sys/bus/platform/drivers/vimc"
#define VIMC_DEV	"vimc.0"
#define MAX_NODES	32
#define N_THREADS	16
#define PHASE_SECONDS	60

static atomic_int stop;
static atomic_long n_ok, n_enodev, n_enoent, n_other_err;
static atomic_long n_cycles, n_bind_err, n_unbind_err, n_no_node;

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

static void count_err(int err)
{
	if (err == ENODEV)
		n_enodev++;
	else if (err == ENOENT)
		n_enoent++;
	else
		n_other_err++;
}

static void *opener(void *arg)
{
	unsigned int seed = (unsigned long)arg;
	char path[PATH_MAX];

	while (!stop) {
		int fd;

		if (pick_node(path, sizeof(path), seed++)) {
			n_no_node++;
			continue;
		}
		fd = open(path, O_RDWR);
		if (fd < 0) {
			count_err(errno);
			continue;
		}
		n_ok++;
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

		if (pick_node(path, sizeof(path), seed++)) {
			n_no_node++;
			continue;
		}
		fd = open(path, O_RDWR);
		if (fd < 0)
			continue;
		/* Keep the handle across an unbind and keep asking. */
		for (i = 0; i < 2000 && !stop; i++) {
			memset(&ctrls, 0, sizeof(ctrls));
			ctrls.which = V4L2_CTRL_WHICH_CUR_VAL;
			if (ioctl(fd, VIDIOC_G_EXT_CTRLS, &ctrls) < 0) {
				int err = errno;

				/* No control handler on this node: pick another. */
				if (err == ENOTTY)
					break;
				count_err(err);
				if (err == ENODEV)
					break;
			} else {
				n_ok++;
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
		if (write_str(VIMC_DRV "/unbind", VIMC_DEV) < 0)
			n_unbind_err++;
		msleep(period_ms);
		if (write_str(VIMC_DRV "/bind", VIMC_DEV) < 0)
			n_bind_err++;
		msleep(period_ms);
		n_cycles++;
	}
	return NULL;
}

static void run_phase(const char *what, unsigned int period_ms)
{
	void *(*fn)(void *) = strcmp(what, "open") ? ioctler : opener;
	pthread_t t[N_THREADS + 1];
	unsigned long i;

	stop = 0;
	n_ok = n_enodev = n_enoent = n_other_err = 0;
	n_cycles = n_bind_err = n_unbind_err = n_no_node = 0;

	for (i = 0; i < N_THREADS; i++)
		pthread_create(&t[i], NULL, fn, (void *)(i * 7));
	pthread_create(&t[N_THREADS], NULL, unbinder,
		       (void *)(unsigned long)period_ms);

	sleep(PHASE_SECONDS);
	stop = 1;
	for (i = 0; i <= N_THREADS; i++)
		pthread_join(t[i], NULL);

	/* Leave vimc bound for the next phase. */
	write_str(VIMC_DRV "/bind", VIMC_DEV);

	printf("RACE-PHASE what=%s period=%ums seconds=%u cycles=%ld ok=%ld enodev=%ld enoent=%ld other_err=%ld no_node=%ld unbind_err=%ld bind_err=%ld\n",
	       what, period_ms, PHASE_SECONDS, (long)n_cycles, (long)n_ok,
	       (long)n_enodev, (long)n_enoent, (long)n_other_err,
	       (long)n_no_node, (long)n_unbind_err, (long)n_bind_err);
	fflush(stdout);
}

int main(void)
{
	char path[PATH_MAX];
	struct stat st;

	mount("proc", "/proc", "proc", 0, NULL);
	mount("sysfs", "/sys", "sysfs", 0, NULL);
	mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);

	if (stat(VIMC_DRV "/" VIMC_DEV, &st)) {
		printf("RACE-ERROR vimc.0 not bound at start\n");
		goto out;
	}
	if (pick_node(path, sizeof(path), 0)) {
		printf("RACE-ERROR no /dev/v4l-subdev* nodes at start\n");
		goto out;
	}

	printf("RACE-START\n");
	fflush(stdout);
	run_phase("open", 1);
	run_phase("open", 30);
	run_phase("ioctl", 1);
	run_phase("ioctl", 30);
	printf("RACE-END\n");

out:
	fflush(stdout);
	sync();
	sleep(1);
	reboot(RB_POWER_OFF);
	return 0;
}
