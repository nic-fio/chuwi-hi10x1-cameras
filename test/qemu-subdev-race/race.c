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
 * The phases to run come from the kernel command line, e.g.
 * "race.phases=open:1,ioctl:30"; the host boots a fresh kernel for each
 * phase, because the threads an oops kills never release the nodes they
 * hold open, and after enough of them vimc cannot be bound again.
 *
 * Each oops kills the thread that hit it, not PID 1. Dead workers are
 * noticed with pthread_tryjoin_np() and re-created (up to MAX_RESPAWN per
 * phase), so a phase keeps exercising its path after the first crashes;
 * "killed" must then match the oopses the host counts in that phase. The kernel log goes to the serial
 * console, which the host saves and counts; this program only reports
 * whether each phase really exercised the path (RACE-PHASE lines), so
 * that a hung or idle run cannot pass for a clean one.
 *
 * Build: gcc -O2 -Wall -static -pthread -o init race.c
 */
#define _GNU_SOURCE
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
#include <sys/resource.h>
#include <sys/stat.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#include <linux/videodev2.h>

#define VIMC_DRV	"/sys/bus/platform/drivers/vimc"
#define VIMC_DEV	"vimc.0"
#define MAX_NODES	32
#define N_THREADS	16
#define PHASE_SECONDS	60
#define MAX_RESPAWN	500

static atomic_int stop;
static atomic_long n_ok, n_enodev, n_enoent, n_other_err;
static atomic_long n_cycles, n_bind_err, n_unbind_err, n_no_node;
static atomic_int first_bind_errno, first_unbind_errno;

static void flush_out(void)
{
	fflush(stdout);
	tcdrain(STDOUT_FILENO);
}

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
		int err;

		err = write_str(VIMC_DRV "/unbind", VIMC_DEV);
		if (err < 0 && !n_unbind_err++)
			first_unbind_errno = -err;
		msleep(period_ms);
		err = write_str(VIMC_DRV "/bind", VIMC_DEV);
		if (err < 0 && !n_bind_err++)
			first_bind_errno = -err;
		msleep(period_ms);
		n_cycles++;
	}
	return NULL;
}

static void run_phase(const char *what, unsigned int period_ms)
{
	void *(*fn)(void *) = strcmp(what, "open") ? ioctler : opener;
	long killed = 0, create_err = 0, respawn = 0;
	int alive[N_THREADS], unbinder_dead = 0;
	pthread_t t[N_THREADS], ub;
	struct timespec start, now;
	unsigned long i;

	stop = 0;
	n_ok = n_enodev = n_enoent = n_other_err = 0;
	n_cycles = n_bind_err = n_unbind_err = n_no_node = 0;
	first_bind_errno = first_unbind_errno = 0;

	for (i = 0; i < N_THREADS; i++) {
		alive[i] = !pthread_create(&t[i], NULL, fn, (void *)i);
		if (!alive[i])
			create_err++;
	}
	if (pthread_create(&ub, NULL, unbinder, (void *)(unsigned long)period_ms)) {
		printf("RACE-ERROR cannot create the unbind thread\n");
		flush_out();
		stop = 1;
		unbinder_dead = 1;
	}

	/* Workers only return when told to stop: an early exit is a death. */
	clock_gettime(CLOCK_MONOTONIC, &start);
	do {
		msleep(10);
		for (i = 0; i < N_THREADS; i++) {
			if (!alive[i] || pthread_tryjoin_np(t[i], NULL))
				continue;
			killed++;
			alive[i] = 0;
			if (respawn < MAX_RESPAWN) {
				respawn++;
				alive[i] = !pthread_create(&t[i], NULL, fn,
							   (void *)(i + respawn));
				if (!alive[i])
					create_err++;
			}
		}
		if (!unbinder_dead && !pthread_tryjoin_np(ub, NULL))
			unbinder_dead = 1;
		clock_gettime(CLOCK_MONOTONIC, &now);
	} while (!stop && now.tv_sec - start.tv_sec < PHASE_SECONDS);

	stop = 1;
	for (i = 0; i < N_THREADS; i++)
		if (alive[i])
			pthread_join(t[i], NULL);
	if (!unbinder_dead)
		pthread_join(ub, NULL);

	/* Leave vimc bound for the next phase. */
	write_str(VIMC_DRV "/bind", VIMC_DEV);

	printf("RACE-PHASE what=%s period=%ums seconds=%u cycles=%ld ok=%ld enodev=%ld enoent=%ld other_err=%ld no_node=%ld killed=%ld create_err=%ld unbinder_dead=%d unbind_err=%ld unbind_errno=%d bind_err=%ld bind_errno=%d\n",
	       what, period_ms, PHASE_SECONDS, (long)n_cycles, (long)n_ok,
	       (long)n_enodev, (long)n_enoent, (long)n_other_err,
	       (long)n_no_node, killed, create_err, unbinder_dead,
	       (long)n_unbind_err, (int)first_unbind_errno,
	       (long)n_bind_err, (int)first_bind_errno);
	flush_out();
}

/* Runs the phases listed in race.phases=what:period[,what:period...]. */
static int run_cmdline_phases(void)
{
	char buf[4096], *p, *tok, *save;
	int fd, n, done = 0;

	fd = open("/proc/cmdline", O_RDONLY);
	if (fd < 0)
		return -1;
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return -1;
	buf[n] = '\0';

	p = strstr(buf, "race.phases=");
	if (!p)
		return -1;
	p += strlen("race.phases=");
	p[strcspn(p, " \n")] = '\0';

	for (tok = strtok_r(p, ",", &save); tok; tok = strtok_r(NULL, ",", &save)) {
		char *colon = strchr(tok, ':');
		unsigned int period;

		if (!colon)
			return -1;
		*colon = '\0';
		period = strtoul(colon + 1, NULL, 10);
		if ((strcmp(tok, "open") && strcmp(tok, "ioctl")) || !period)
			return -1;
		run_phase(tok, period);
		done++;
	}
	return done ? 0 : -1;
}

int main(void)
{
	char path[PATH_MAX];
	struct stat st;

	mount("proc", "/proc", "proc", 0, NULL);
	mount("sysfs", "/sys", "sysfs", 0, NULL);
	mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);

	/*
	 * A thread killed inside open() never releases the descriptor slot
	 * the syscall had reserved; with the default limit of 1024, about a
	 * thousand deaths make every later open() fail with EMFILE, including
	 * the unbind thread's writes to sysfs.
	 */
	struct rlimit rl = { 1 << 20, 1 << 20 };

	if (setrlimit(RLIMIT_NOFILE, &rl))
		printf("RACE-NOTE cannot raise RLIMIT_NOFILE: %d\n", errno);

	if (stat(VIMC_DRV "/" VIMC_DEV, &st)) {
		printf("RACE-ERROR vimc.0 not bound at start\n");
		goto out;
	}
	if (pick_node(path, sizeof(path), 0)) {
		printf("RACE-ERROR no /dev/v4l-subdev* nodes at start\n");
		goto out;
	}

	printf("RACE-START\n");
	flush_out();
	if (run_cmdline_phases()) {
		printf("RACE-ERROR bad or missing race.phases= on the command line\n");
		goto out;
	}
	printf("RACE-END\n");

out:
	flush_out();
	sync();
	sleep(1);
	reboot(RB_POWER_OFF);
	return 0;
}
