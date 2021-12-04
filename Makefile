TARGET_EXEC := sriw16

CC = gcc

CFLAGS = -Wall -Wextra

LDFLAGS = -O3

SRC_DIR = src
BUILD_DIR = build

HEADERS = $(shell find ${SRC_DIR} -name *.h)
SRCS = $(shell find ${SRC_DIR} -name *.c)

build: $(SRCS) $(HEADERS)
	mkdir -p $(BUILD_DIR)
	$(CC) -o $(BUILD_DIR)/${TARGET_EXEC} $(SRCS) $(LDFLAGS) $(CFLAGS)

.PHONY = clean

clean:
	-@rm -r $(BUILD_DIR)

