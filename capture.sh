#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$PROJECT_DIR"

run_timed() {
  /usr/bin/time -p "$@"
}

: "${RUNTIME_DIR:?RUNTIME_DIR must point to the OpenCode web runtime}"
: "${CAPTURE_URL:?Set CAPTURE_URL to the exact page URL to capture}"
: "${CAPTURE_DIR:?Set CAPTURE_DIR to the screenshot output directory}"

# Validate the URL and normalize/create the evidence directory. Keep evidence
# outside the project so captures never become source or deployment content.
CAPTURE_DIR="$(run_timed node - "$PROJECT_DIR" "$CAPTURE_DIR" "$CAPTURE_URL" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const [projectArg, outputArg, urlArg] = process.argv.slice(2);
let url;
try { url = new URL(urlArg); } catch { throw new Error('CAPTURE_URL must be an absolute HTTP(S) URL.'); }
if (!['http:', 'https:'].includes(url.protocol)) throw new Error('CAPTURE_URL must use HTTP or HTTPS.');
const project = fs.realpathSync(projectArg);
const output = path.resolve(outputArg);
if (output === project || output.startsWith(project + path.sep)) {
  throw new Error('CAPTURE_DIR must be outside the project directory.');
}
fs.mkdirSync(output, { recursive: true });
process.stdout.write(output);
NODE
)"
export CAPTURE_DIR

PLAYWRIGHT_DIR="${HOME:?HOME is not set}/.local/share/omgithub-playwright"
for prerequisite in \
  "$RUNTIME_DIR/scripts/default-capture.mjs" \
  "$PLAYWRIGHT_DIR/linux.json" \
  "$PLAYWRIGHT_DIR/display" \
  "$PLAYWRIGHT_DIR/node_modules/playwright/package.json"; do
  if ! run_timed test -f "$prerequisite"; then
    echo "Browser capture prerequisite is unavailable: $prerequisite" >&2
    exit 75
  fi
done

# Strict mode makes runtime page errors and same-origin failed requests render
# defects (exit 1); the runtime helper maps browser/navigation outages to 75.
export CAPTURE_STRICT=1
set +e
run_timed node "$RUNTIME_DIR/scripts/default-capture.mjs"
status=$?
set -e
if (( status != 0 )); then
  exit "$status"
fi

# Fail as a script/rendering defect if either expected screenshot was not saved
# as a non-empty PNG by the browser helper.
run_timed node - "$CAPTURE_DIR" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const directory = process.argv[2];
for (const name of ['final-desktop.png', 'final-mobile.png']) {
  const file = path.join(directory, name);
  const data = fs.readFileSync(file);
  if (data.length < 100 || data.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') {
    throw new Error(`Missing or invalid screenshot: ${file}`);
  }
}
NODE
