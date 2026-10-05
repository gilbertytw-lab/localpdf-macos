#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
for file in AGENTS.md REVIEW.md LICENSE intent/mac-mvp/intent.md intent/mac-mvp/spec.md intent/mac-mvp/plan.md intent/direct-content-edit/intent.md intent/direct-content-edit/spec.md intent/direct-content-edit/plan.md intent/inline-content-edit/intent.md intent/inline-content-edit/spec.md intent/inline-content-edit/plan.md intent/page-management-workspace/intent.md intent/page-management-workspace/spec.md intent/page-management-workspace/plan.md intent/editable-text-boxes/intent.md intent/editable-text-boxes/spec.md intent/editable-text-boxes/plan.md intent/comment-threads/intent.md intent/comment-threads/spec.md intent/comment-threads/plan.md intent/selected-text-comments/intent.md intent/selected-text-comments/spec.md intent/selected-text-comments/plan.md docs/risk-policy.md; do
    test -s "$file" || { echo "Missing artifact: $file"; exit 1; }
done
# Native engine headers contain upstream documentation URLs; app code has no network capability.
if rg -n 'https?://|URLSession|NWConnection|WKWebView|JavaScriptCore|Process\(' Sources/LocalPDF Sources/LocalPDFCore Sources/CPDFium/save.c Package.swift; then
    echo 'Network/process capability added: requires a new reviewed specification.'
    exit 1
fi
if ! rg -q 'Sources/LocalPDFCore/' intent/mac-mvp/plan.md; then
    echo 'Core source paths missing from implementation plan.'
    exit 1
fi
rg -q 'Sources/CPDFium/' intent/direct-content-edit/plan.md
rg -q 'pdf_enable_v8 = false' .build/deps/pdfium/args.gn
rg -q 'pdf_enable_xfa = false' .build/deps/pdfium/args.gn
git ls-files --cached --others --exclude-standard | while IFS= read -r path; do
    case "$path" in
        AGENTS.md|REVIEW.md|README.md|LICENSE|.gitignore|Package.swift|Makefile|intent/*|docs/*|evals/*|Sources/CPDFium/*|Sources/LocalPDFCore/*|Sources/LocalPDF/*|Tests/LocalPDFCoreTests/*|scripts/*) ;;
        *) echo "Unplanned path: $path"; exit 1 ;;
    esac
done
echo 'Local artifact, offline capability and planned-path checks passed.'
