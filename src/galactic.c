#include "galactic.h"

int main(int argc, char** argv) {


	if (argc < 2 || argc > 3){
		fprintf(stderr, "Error: Wrong number of arguments, call SRIW-16 with the following arguments:\n");
		fprintf(stderr, "%s <memory image> [storage image]\n", argv[0]);
		return 3;
	}

	int load_status = load_program(argv[1]);

	if (load_status) {
		return load_status;
	}

	
	#ifdef __unix__ // set up tty stuff
	init_tty();

	init_signals();
	#endif
	
	running = 1;
	registers[15] = 0; // program counter

	int return_value = 0;
	uint16_t cycles = 1; // instruction counter, allow time for setup

	while (running) {
		input_wrapper(cycles);
		
		return_value = do_instruction();
		if (return_value) running = 0;

		cycles = (cycles + 1) % CYCLE_LOOP;
	}

	if (return_value == 255) return_value = 0;
	quit(return_value);
}

int do_instruction() {
	int rv = 0;	
	uint16_t instruction = (memory[registers[15]]);

	uint8_t opcode = (instruction & 0xf000) >> 12;
	uint8_t reg1 = (instruction & 0x0f00) >> 8;
	uint8_t reg2 = (instruction & 0x00f0) >> 4;
	uint8_t reg3 = (instruction & 0x000f);

	registers[15] += 1;

	switch (opcode) {
		case HALT:
			rv = 255;
			break;
		case LOAD:
			registers[reg1] = memory[registers[reg2] + registers[reg3]];
			break;
		case STORE:
			memory[registers[reg1] + registers[reg2]] = registers[reg3];
			if (registers[reg1] + registers[reg2] == MMIO_OUTPUT) // no escape codes
				if (memory[registers[reg3]] != 27 && memory[registers[reg3]] < 256)
					putchar(registers[reg3]);
			break;
		case ADD:
			registers[reg1] = registers[reg2] + registers[reg3];
			break;
		case SUB:
			registers[reg1] = registers[reg2] - registers[reg3];
			break;
		case CMPA: // refactor into function later
			registers[reg1] = compare(registers[reg2] + registers[reg3], reg1, reg2, reg3);
			break;
		case CMPS:
			registers[reg1] = compare(registers[reg2] - registers[reg3], reg1, reg2, reg3);
			break;
		case BRANCH:
			if ((registers[reg2] & reg3) == reg3)
				registers[15] = registers[reg1];
			break;
		case SHIFT:
			if ((int16_t) registers[reg3] < 0)
				registers[reg1] = registers[reg2] << registers[reg3];
			else
				registers[reg1] = registers[reg2] >> registers[reg3];
			break;
		case AND:
			registers[reg1] = registers[reg2] & registers[reg3];
			break;
		case OR:
			registers[reg1] = registers[reg2] | registers[reg3];
			break;
		case XOR:
			registers[reg1] = registers[reg2] ^ registers[reg3];
			break;
		case NOR:
			registers[reg1] = (registers[reg2] | registers[reg3]);
			break;
		case MSB:
			registers[reg1] = (memory[registers[reg2] + registers[reg3]]) & 0xff;
			break;
		case LSB:
			registers[reg1] = ((memory[registers[reg2] + registers[reg3]]) & 0xff00) >> 8;
			break;
		case BYTE:
			registers[reg1] = instruction & 0xff;
			break;
	}

	return rv;
}

uint16_t compare(uint16_t cmp_temp, uint16_t r1, uint16_t r2, uint16_t r3) {
	uint16_t flags_temp = registers[r1];

	// carry
	if (cmp_temp < registers[r2] || cmp_temp < registers[r3])
		flags_temp |= 0b1000;
	else
		flags_temp &= 0b1111111111110111; // 16 bits

	// overflow
	if ((int16_t) (registers[r2] ^ registers[r3]) >= 0 && (int16_t) (registers[r2] ^ cmp_temp) < 0)
		flags_temp |= 0b0100;
	else
		flags_temp &= 0b1111111111111011; // 16 bits

	// negative
	if (cmp_temp & 0x8000)
		flags_temp |= 0b0010;
	else
		flags_temp &= 0b1111111111111101; // 16 bits

	// zero
	if (cmp_temp == 0)
		flags_temp |= 0b0001;
	else
		flags_temp &= 0b1111111111111110; // 16 bits

	return flags_temp;
}

void input_wrapper(uint16_t cycle) {
	int c = input();
	if (c != -1 && c != 0 && !cycle) {
		memory[MMIO_INPUT] = c;
	}
}

void quit(int status) {

#ifdef __unix__ // only do tty stuff for unix-based systems
	reset_tty();
#endif

	exit(status);
}

#ifdef _WIN32

int input() {
	if (_kbhit()) {
		int c = _getch();
		if (c == 0 || c == 224) {
			_getch();
			return -1;
		}

		return c;
	}
	return 0;
}

#elif defined __unix__

int input() {
	char c = '\0';
	int poll_res = poll(&fd, 1, INPUT_TIMEOUT);

	if (poll_res == -1) return -1;
	if (!poll_res) return 0;
	if (fd.revents & POLLIN) read(STDIN_FILENO, &c, 1);
	return c;
}

void init_tty() {
	tcgetattr(STDIN_FILENO, &old); /* grab old terminal i/o settings */
	raw = old; /* make new settings same as old settings */
	raw.c_lflag &= ~ICANON; /* disable buffered i/o */
	raw.c_cc[VMIN] = 0; // no bytes required before timeout
	raw.c_cc[VTIME] = 1; // time out in 10ms
	tcsetattr(STDIN_FILENO, TCSANOW, &raw); /* use these new terminal i/o settings now */

	fd.fd = STDIN_FILENO;
	fd.events = POLLIN;
}

void init_signals() {
	signal(SIGTSTP, suspend_sig);
	signal(SIGINT, quit_sig);
	signal(SIGQUIT, quit_sig);
	signal(SIGABRT, quit_sig);
	signal(SIGSEGV, quit_sig);
	signal(SIGBUS, quit_sig);
	signal(SIGFPE, quit_sig);
	signal(SIGILL, quit_sig);
	signal(SIGSEGV, quit_sig);
	signal(SIGSYS, quit_sig);
	signal(SIGTRAP, quit_sig);
	signal(SIGXCPU, quit_sig);
	signal(SIGXFSZ, quit_sig);
	signal(SIGCONT, resume_sig);
}

void reset_tty() {
	tcsetattr(0, TCSANOW, &old);
}

void suspend_sig() {
	reset_tty();
	kill(getpid(), SIGSTOP); // compatible with pre-ISO unixes, raise is not
}

void resume_sig() {
	init_signals();
	init_tty();
}

void quit_sig() {
	quit(-1);
}

#endif

int load_program(char *filename) {
	uint32_t filelen;

	FILE *file = fopen(filename, "rb");

	if (!file) {
	fprintf(stderr, "Error: Could not open input file\n");
		return 1;
	}

	fseek(file, 0, SEEK_END);
	filelen = ftell(file);
	fseek(file, 0, SEEK_SET);

	if (filelen > AVAILABLE_RAM - MMIO_SIZE) {
		fprintf(stderr, "Error: File too large at %d bytes, the maximum file size is %d bytes\n", filelen, AVAILABLE_RAM - MMIO_SIZE);
			fclose(file);
				return 2;
	}

	fread(memory, 2, filelen, file);
	fclose(file);

	return 0;
}
