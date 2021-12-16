#ifndef RIW16_H
#define RIW16_H


// platform specific stuff

#ifdef _WIN32

#include <conio.h>

#elif defined __unix__

#include <termios.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/poll.h>
#include <sys/time.h>
#include <time.h>

#define INPUT_TIMEOUT 0

void init_tty();
void init_signals();
void init_keytimer();
void reset_tty();
void suspend_sig();
void resume_sig();
void quit_sig();

struct pollfd fd;
static struct termios old, raw;

#else

#error Unsupported Platform

#endif


// general includes

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// memory macros

#define AVAILABLE_RAM 0x10000
#define MMIO_SIZE     0x6
#define MMIO_CHAROUT  AVAILABLE_RAM - 0x1
#define MMIO_CHARIN   AVAILABLE_RAM - 0x2
#define MMIO_STOREIO  AVAILABLE_RAM - 0x3
#define MMIO_STOREMSW AVAILABLE_RAM - 0x4
#define MMIO_STORELSW AVAILABLE_RAM - 0x5
#define MMIO_HALT     AVAILABLE_RAM - 0x6

// instruction macros

#define LOCT   0b0000
#define LOAD   0b0001
#define STORE  0b0010
#define ADD    0b0011
#define SUB    0b0100
#define CMPA   0b0101
#define CMPS   0b0110
#define BRANCH 0b0111
#define SHIFT  0b1000
#define AND    0b1001
#define OR     0b1010
#define XOR    0b1011
#define NOR    0b1100
#define MSO    0b1101
#define LSO    0b1110
#define UOCT   0b1111


// flag macros

#define CARRY    0b1000
#define OVERFLOW 0b0100
#define NEGATIVE 0b0010
#define ZERO     0b0001


// misc macros

#define INPUT_LOOP    32
#define STORAGE_LOOP  256
#define STORAGE_SPACE 0x400000


// arrays

uint16_t memory[AVAILABLE_RAM];
uint16_t registers[16];


// variables

uint8_t running;
FILE* storage;
char* storage_name; // argv[2] if it exists, otherwise empty string
uint16_t is_storage_open; // 0 if file is closed, counts up if open, modulo INPUT_LOOP

// functions

int do_instruction();
uint16_t compare(uint16_t cmp_temp, uint16_t r1, uint16_t r2, uint16_t r3);
int check_halt(uint16_t address);
void input_wrapper(uint16_t* result);
int input();
void quit();
void printchar(int c);

int load_program(char* filename);
void write_storage(uint16_t data);
void read_storage(uint16_t* data);
int open_storage();

void millisleep(unsigned int ms);
#endif
