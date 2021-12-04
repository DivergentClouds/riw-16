TARGET_EXEC_UNIX := sriw16
TARGET_EXEC_WIN := sriw16.exe

CC = gcc

CFLAGS = -Wall -Wextra

LDFLAGS = -O3

SRC_DIR = src
BUILD_DIR = build

HEADERS = $(shell find ${SRC_DIR} -name *.h)
SRCS = $(shell find ${SRC_DIR} -name *.c)

.PHONY = clean linux windows

linux: $(SRCS) $(HEADERS)
	mkdir -p $(BUILD_DIR)
	$(CC) -o $(BUILD_DIR)/${TARGET_EXEC_UNIX} $(SRCS) $(LDFLAGS) $(CFLAGS)

windows: $(SRCS) $(HEADERS)
	mkdir -p $(BUILD_DIR)
	$(CC) -o $(BUILD_DIR)/${TARGET_EXEC_WIN} $(SRCS) $(LDFLAGS) $(CFLAGS)

clean:
	-@rm -r $(BUILD_DIR)

