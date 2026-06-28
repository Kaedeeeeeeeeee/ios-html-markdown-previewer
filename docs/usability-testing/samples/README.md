# Sample Files

Use these files for first-round external open and usability testing:

- `basic-report.html`: single-file HTML with inline styling.
- `legacy-report.htm`: `.htm` extension coverage for external open validation.
- `markdown-notes.md`: common Markdown coverage.
- `markdown-reference.markdown`: `.markdown` extension coverage for external open validation.
- `zip-report.zip`: HTML package with local CSS and SVG image assets.
- `external-resource.html`: references remote CSS, image, and JavaScript to verify Safe Preview blocking.
- `interactive-trusted.html`: local JavaScript interaction used to evaluate the Safe Preview vs Interactive mode decision.
- `broken.zip`: intentionally invalid ZIP file used to verify the error path.

To stage a clean folder and distribution ZIP for a physical device, run:

```sh
scripts/prepare-validation-samples.sh
```

The generated distribution ZIP is only for moving the sample set to a device. After expanding it in Files, use the individual files for testing.

Regenerate `zip-report.zip` from `zip-report-source/` after editing the source files:

```sh
cd docs/usability-testing/samples/zip-report-source
zip -r ../zip-report.zip .
```
