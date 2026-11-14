# ABOUTME: Build and test commands for the jumping jack Connect IQ app.
# ABOUTME: `make build` compiles, `make test` runs unit tests, `make install` copies the app to a USB-mounted watch.
# SDK 9.1's test runner hangs when a test fails; 9.3 reports the failure and exits.
SDK_DIR ?= $(HOME)/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.3.0-2026-10-20-95888f262
DEVICE ?= instinct2
KEY ?= $(HOME)/Documents/developer_key
WATCH ?= /Volumes/GARMIN
APP := bin/JUMPING.prg
TEST_APP := bin/jumping-test.prg

build:
	"$(SDK_DIR)/bin/monkeyc" -f monkey.jungle -d $(DEVICE) -y "$(KEY)" -o $(APP) -l 3 -w

test:
	"$(SDK_DIR)/bin/monkeyc" -f monkey.jungle -d $(DEVICE) -y "$(KEY)" -o $(TEST_APP) -l 3 -w --unit-test
	# monkeydo exits 1 whether tests pass or fail, so the summary line decides the result.
	"$(SDK_DIR)/bin/monkeydo" $(TEST_APP) $(DEVICE) -t | tee bin/test-results.txt; \
	grep -q '^PASSED' bin/test-results.txt

# dot_clean removes macOS ._ metadata files, which the watch rejects as apps with failed signatures.
install: build
	cp $(APP) "$(WATCH)/GARMIN/APPS/"
	dot_clean -m "$(WATCH)/GARMIN/APPS"
	diskutil eject "$(WATCH)"

simulator:
	open "$(SDK_DIR)/bin/ConnectIQ.app"

.PHONY: build test install simulator
