# Sample Files

Use these files for first-round external open and usability testing:

- `basic-report.html`: single-file HTML with inline styling.
- `markdown-notes.md`: common Markdown coverage.
- `zip-report.zip`: HTML package with local CSS and SVG image assets.
- `external-resource.html`: references remote CSS, image, and JavaScript to verify Safe Preview blocking.
- `interactive-trusted.html`: local JavaScript interaction used to evaluate the Safe Preview vs Interactive mode decision.
- `broken.zip`: intentionally invalid ZIP file used to verify the error path.

Regenerate `zip-report.zip` from `zip-report-source/` after editing the source files:

```sh
cd docs/usability-testing/samples/zip-report-source
zip -r ../zip-report.zip .
```
