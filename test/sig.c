#include <signal.h>
#include <stdio.h>
#include <unistd.h>

void handle() {
	printf("I won't die that easily!\n");
}

int main() {
	struct sigaction sa = {0};
	sa.sa_handler = handle;

	sigaction(SIGINT, &sa, NULL);

	int i = 0;
	while (i < 60) {
		printf("sleep %d\n", i);
		sleep(1);

		i++;
	}
}
