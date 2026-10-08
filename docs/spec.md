

 | 

Threads and Synchronization: Presidential Debate
# Project Overview
The first 2020 presidential debate is held in UMAss Amherst by CPD (Commission on Presidential Debates), which chooses a different format for this debate that the questions for candidates are collected from audiences. This assignment is a simulation of calling to propose questions by multiple audiences at the same time. This is a tricky assignment that illustrates threads, synchronization, and critical sections. The code is not long, but the details are subtle. You will write a simulation to post the questions from a phone answering system in the CPD. 

Let us imagine that to post a question each person must make a phone call to the call center of CPD as soon as the debate starts. Here we will assume that there are five call lines, but only two operators. When a phone call arrives, we check if there is a free line. If so, the phone rings and the caller is considered connected; otherwise it is busy. Once the phone rings, we wait until there is a free operator. When we get one, we simulate the process of proposing a question. Each phone call is represented by a thread, and you may have more threads running than phone lines.

There are several components to the project, as specified below.
# Semaphores
A semaphore provides a mechanism to avoid race conditions. In general, it provides mutually exclusive access to a resource. We can easily simulate a lock using a binary semaphore:

sem_t lock;  int main() {   sem_init(&lock, 0, 1);   pthread_t tid1, tid2;   pthread_create(&tid1, NULL, phonecall, NULL);   pthread_create(&tid2, NULL, phonecall, NULL);   ... }  void* phonecall(void* vargp) {   sem_wait(&lock);   // critical section   sem_post(&lock); }


In this case, we initialize the semaphore (lock) to 1. This indicates that only 1 thread may be allowed to enter a critical section. This is typically referred to as a binary semaphore. What if we want to allow more than 1 thread into a section of code? For the problem we are trying to solve we have a limited resource (operators), but we have many phone calls that are being made to the phone system concurrently. We can easily make a change to the initialization of the semaphore such that it allows more than 1 thread into a section of code at a time. Assuming we want to model two operators as a resource, we would create and initialize the semaphore like so:

sem_t operators; sem_init(&operators, 0, 2);


We would then have something like the following code in each phone call thread:

sem_wait(&operators); // Proceed with question proposal process sem_post(&operators);


So, the binary semaphore provides exclusive access for a single thread to a critical section of code, whereas an n-ary semaphore, typically referred to as a counting semaphore, provides a limit of n threads to n resources. For this simulation you will need to use both concepts to restrict access for 1 thread to alter the shared state for the number of connected callers and to allow multiple threads to gain access to a limited number of operators.
# Phone Calls
A phone call is represented by a thread function that will have a caller’s id as a function local variable. The id variable is initialized by incrementing a global variable called next_id and assigning it to the id variable inside the thread function. Do you need synchronization here? The idea is that each time a new thread is created it will get a unique id that can be used to identify its output. To make things simple initially, write a thread function called phonecall that prints a message “this is a phone call” before the thread function ends. Later you will do the meaty part of the simulation.

Your main thread function will declare an array of thread id’s (pthread_t) that will represent each phone call. The total number of phone calls is 200, but the total seconds of the debate is determined as being passed in as a command line argument. Your program then writes a loop calling pthread_create given the phonecall thread function and each corresponding entry of the array of thread id’s. After we create all of the phonecall threads, we want to block the main thread until the debate time finishes to simulate the actual debate. To do that, you need to create another thread as a timer and have the main thread use pthread_join on this thread. When the timer thread finishes, your main thread needs to terminate all threads.
# Synchronization
Once you have the threads going, you'll want to do the real part of the simulation. To support your phonecall thread function you should declare the following static data as global variables and initialize the semaphores properly:

static sem_t connected_lock;static sem_t operators;static int NUM_OPERATORS = 2; static int NUM_LINES = 5;static int connected = 0;    // Callers that are connected void* phonecall(void* vargp) {       ... }


The variable connected tells us how many callers are currently connected (a call attempt is declared busy if connected==NUM_LINES). Access to connected must be controlled by a critical section, and is done by using the connected_lock binary semaphore. The operators counting semaphore is used once a call connects with an operator. Here is a sketch of the phonecall thread function algorithm:

- Print that an attempt to connect has been made.
- Check if the connection can be made:
- You'll need to test connected in a critical section.
- If the line is busy, exit the critical section and try again in 1 second.
- If the line is not busy, update connected, exit the critical section, and print a message, and continue to the next step.
- Wait for an operator to be available (using a counting semaphore).
- Print a message that the question is being taken by an operator.
- Simulate a question proposal by sleeping for 1 second (sleep(3)).
- Print a message that the question proposal is complete (and update the semaphore).
- Update connected (using a binary semaphore).
- Print a message that the call is over.

Make sure that your output has the caller’s id to distinguish the output between different callers. Your program should print out something like the following:

...Thread [CALLER_ID] is attempting to connect ... Thread [CALLER_ID] connects to an available line, call ringing ... Thread [CALLER_ID] is speaking to an operator. Thread [CALLER_ID] has proposed a question for candidates! The operator has left ... Thread [CALLER_ID] has hung up!...


Note that [CALLER_ID] is the value of the id variable as specified above (under the Phone Calls section).

Write all your code in a single presidential_debate.c file.
# Testing
- Test your program by running with 3 second debate.
- Test your program by running with 10 second debate.
- Test your program by running with 20 second debate.
- Test your program by running with 50 second debate.
- Test your program by running with 100 second debate.

# Video Demonstration
You must provide a link to a 2-minute video demonstration. Your video should be short and get to the point, showing your program being compiled and executed. The video should demonstrate three different tests, with 3 second debate, 10 second debate, and 100 second debate, respectively. You must use your voice to guide the watcher and demonstrate all required outputs.
# Grading Breakdown
- Project Requirements (40 points)
- Binary semaphores are used properly to protect critical regions of code.
- Binary semaphores are used properly not to protect non-critical regions of code.
- A counting semaphore is used properly to restrict the use of resources (operators).
- All semaphores are correctly initialized and destroyed.
- A thread function exists and is implemented properly.
- Threads are created, detached, and joined properly.
- A global variable next_id exists and is properly updated in the thread function and used to set the caller’s id.
- The phonecall thread properly updates the shared state for the number of connected callers in a critical section.
- The program prints properly formatted outputs with the caller’s id.
- The static modifier is used properly for both thread local variables as well as any global variables.
- Design and Implementation (30 points)
- Functions are declared and used properly.
- Data structures and data types are declared and used properly.
- Variable and function naming is clear and helps with understanding the purpose of the program.
- Global variables are minimized, declared, and used properly.
- Control flow (e.g., if statements, looping constructs, function calls) are used properly.
- Algorithms are clearly constructed and are efficient. For example, there is no extra looping, unreachable code, confusing or misleading constructions, and missing or incomplete cases.
- Coding Style (5 points)
- Code is written in a consistent style. For example, curly brace placement is the same across all if/then/else and looping constructors.
- Proper and consistent indenting is adhered to across the entire implementation.
- Proper spacing is used making the code understandable and readable.
- Comments (5 points)
- Comments in the code are used to document algorithms.
- Variables are documented such that they aid the reader in understanding your code.
- Functions are documented to indicate the purpose of the parameters and return values.
- Video (14 points)
- The video shows the code being compiled from the command line.
- The video shows the code being executed and satisfies the output requirements.
- The video shows your program running to completion with 3 seconds.
- The video shows your program running to completion with 10 seconds.
- The video shows your program running to completion with 100 seconds.
- README.txt (5 points)
- The README.txt file is well written.
- The README.txt file provides an overview of your implementation.
- The README.txt file explains how your code satisfies each of the requirements. 
- GradeScope Submission (1 point)
- You automatically get a point for submitting to gradescope.
# Submission
You must submit the following to Gradescope by the assigned due date:

- Makefile - the build file to use with the make program.
- Source Files - source and header files that provide the solution to this project.
- README.txt - this is a text file containing an overview/description of your submission highlighting the important parts of your implementation. You should also explain where in your implementation your code satisfies each of the requirements of the project or any requirements that you did not satisfy. The goal should make it easy and obvious for the person grading your submission to find the important rubric items. This text file should also clearly include a URL to your video for us to review. The video should not exceed 2 minutes in length and must provide a recorded voice to guide the viewer. 

You must use the VM environment to write your code. Make sure you submit this project to the correct assignment on Gradescope!
