CC ?= clang
LIBUSB_PREFIX ?= $(shell brew --prefix libusb)

CPPFLAGS += -I$(LIBUSB_PREFIX)/include/libusb-1.0
CFLAGS += -std=c11 -Wall -Wextra -Werror
LDFLAGS += -L$(LIBUSB_PREFIX)/lib -Wl,-rpath,$(LIBUSB_PREFIX)/lib
LDLIBS += -lusb-1.0

BUILD_DIR := build
PROBE := $(BUILD_DIR)/xbox-light-probe
PROBE_SOURCES := xbox_light_probe.c xbox_light_protocol.c xbox_light_options.c xbox_light_endpoint.c

.PHONY: all clean test

all: $(PROBE)

$(PROBE): $(PROBE_SOURCES) xbox_light_protocol.h xbox_light_options.h xbox_light_endpoint.h
	mkdir -p $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(PROBE_SOURCES) $(LDFLAGS) $(LDLIBS) -o $@

test: all
	$(CC) $(CFLAGS) Tests/protocol_tests.c xbox_light_protocol.c -o $(BUILD_DIR)/protocol-tests
	$(BUILD_DIR)/protocol-tests
	$(CC) $(CFLAGS) Tests/options_tests.c xbox_light_options.c -o $(BUILD_DIR)/options-tests
	$(BUILD_DIR)/options-tests
	$(CC) $(CFLAGS) Tests/endpoint_tests.c xbox_light_endpoint.c -o $(BUILD_DIR)/endpoint-tests
	$(BUILD_DIR)/endpoint-tests
	sh Tests/cli_tests.sh

clean:
	rm -rf $(BUILD_DIR)
