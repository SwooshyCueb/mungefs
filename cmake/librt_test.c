#include <sys/types.h>

#include <signal.h>
#include <time.h>

int main(void) {
	timer_t timerid;
	struct sigevent sev;
	timer_create(CLOCK_REALTIME, &sev, &timerid);
	return 0;
}
