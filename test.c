#include <errno.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

#define FORK_CHILD 0

static void error_and_exit(void) {
  //fprintf(stderr, "Error: %s\n", strerror(errno));
  exit(EXIT_FAILURE);
}

static int fork_or_die(void) {
  int pid = fork();
  if (pid == -1) {
    error_and_exit();
  }
  return pid;
}

int main(const int argc, const char * argv[])
{
  int processes = argc - 1;
  int apipe[argc - 1][2];
  int pid;

  char* bruh = (char*)NULL;

  printf("%d%s\n", argc, *bruh);

  int result = -1;
  for (int i = 0; i < processes; i++) {
    result = pipe(apipe[i]);
    if (result == -1) {
      error_and_exit();
    }

  }

  for (int i = 0; i < processes; i++) {

    pid = fork_or_die();

    // Child process executes process
    if (pid == FORK_CHILD) {

      // If we are not the first program in the pipe
      if (i > 0) {
        // Use the output from the previous program in the pipe as our input

        // Check the read end of the pipe and STDIN are different descriptors
        if (apipe[i - 1][0] != STDIN_FILENO) {
          // Send the read end of the pipe to STDIN
          if (dup2(apipe[i - 1][0], STDIN_FILENO) == -1) {
            error_and_exit();
          }
        }
      }

      // Before we execute a process, bind the write end of the pipe to STDOUT
      // Don't do this to the last process in the pipe, just send output to STDOUT as normal
      if (i < processes - 1) {
        // Check the write end of the pipe and STDOUT are different descriptors
        if (apipe[i][1] != STDOUT_FILENO) {

          // Send the write end of the pipe to STDOUT
          if (dup2(apipe[i][1], STDOUT_FILENO) == -1) {
            error_and_exit();
          }
        }
      }

      for (int j = 0; j < processes; j++) {
         if(close(apipe[j][0]) == -1)
         error_and_exit();
         if(close(apipe[j][1]) == -1)
         error_and_exit();
      }

      // Child executes requested process
      if (execlp(argv[i + 1], argv[i + 1], (char *)NULL) == -1) {
        error_and_exit();
      }
    }

  }
   
  // Parent does nothing until loop exits (waits for children)
  for (int i = 0; i < processes; i++) {
         if(close(apipe[i][0]) == -1)
         error_and_exit();
         if(close(apipe[i][1]) == -1)
         error_and_exit();
  }

  for (int i = 0; i < processes; i++) {
      waitpid(-1, NULL, 0);
  }

  return 0;
}
