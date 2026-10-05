.PHONY: deps build bundle run test lint format policy verify ui-check

deps:
	./scripts/prepare-pdfium.sh

build: deps
	swift build

bundle: build
	./scripts/bundle.sh

run: bundle
	open .build/LocalPDF.app

test: deps
	swift test

lint:
	xcrun swift-format lint --strict --recursive Package.swift Sources Tests

format:
	xcrun swift-format format --in-place --recursive Package.swift Sources Tests

policy: deps
	./scripts/check-policy.sh

verify: lint policy test build

ui-check: bundle
	mkdir -p .build/ui-check
	.build/LocalPDF.app/Contents/MacOS/LocalPDF --ui-check "$(CURDIR)/.build/ui-check"
	@if command -v pdftoppm >/dev/null 2>&1; then pdftoppm -f 1 -singlefile -scale-to 1200 -png .build/ui-check/edited.pdf .build/ui-check/pdf-page-1 && pdftoppm -f 3 -l 3 -singlefile -scale-to 1200 -png .build/ui-check/edited.pdf .build/ui-check/pdf-page-3; else echo 'Independent PDF rendering requires Poppler; verify the PDF canvas in the running app.'; fi
