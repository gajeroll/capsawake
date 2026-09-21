.PHONY: build test lint fmt clean
build:
	swift build -c release
test:
	swift test
lint:
	swift format lint --strict --recursive Sources Tests
fmt:
	swift format format --in-place --recursive Sources Tests
clean:
	rm -rf .build dist
