#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$PROJECT_DIR"

run_timed() {
  /usr/bin/time -p "$@"
}

: "${RUNTIME_DIR:?RUNTIME_DIR must point to the OpenCode web runtime}"
PORT="${PORT:-3000}"
export PORT
OUTPUT_DIR="$PROJECT_DIR/dist"
WORKER_META_DIR="${OPENCODE_WEB_DIR:-${RUNNER_TEMP:-/home/runner/work/_temp}/omgithub-web}"
DEPLOYMENT_FILE="$WORKER_META_DIR/deployment-output.json"

run_timed mkdir -p "$OUTPUT_DIR" "$WORKER_META_DIR" "$(dirname -- "$DEPLOYMENT_FILE")"

if [[ -f "$PROJECT_DIR/package.json" ]]; then
  dependency_hash="$(run_timed node -e 'const fs=require("node:fs");const crypto=require("node:crypto");const h=crypto.createHash("sha256");for(const f of ["package.json","package-lock.json","npm-shrinkwrap.json"]){if(fs.existsSync(f))h.update(fs.readFileSync(f));}process.stdout.write(h.digest("hex"));' )"
  dependency_stamp="$WORKER_META_DIR/dependency-hash"
  previous_hash=""
  if [[ -f "$dependency_stamp" ]]; then
    previous_hash="$(run_timed cat "$dependency_stamp")"
  fi
  if [[ ! -d "$PROJECT_DIR/node_modules" || "$dependency_hash" != "$previous_hash" ]]; then
    if [[ -f "$PROJECT_DIR/package-lock.json" || -f "$PROJECT_DIR/npm-shrinkwrap.json" ]]; then
      run_timed npm ci --no-audit --no-fund
    else
      run_timed npm install --no-audit --no-fund
    fi
    run_timed /usr/bin/printf '%s' "$dependency_hash" > "$dependency_stamp"
  fi

  has_build="$(run_timed node -e 'const p=require("./package.json");process.stdout.write(p.scripts&&p.scripts.build?"yes":"no")')"
  if [[ "$has_build" == yes ]]; then
    run_timed npm run build
  elif [[ -f "$PROJECT_DIR/index.html" ]]; then
    run_timed node - "$PROJECT_DIR" "$OUTPUT_DIR" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const source = path.resolve(process.argv[2]);
const output = path.resolve(process.argv[3]);
const excluded = new Set(['.git', '.agents', 'node_modules', 'dist', 'build']);
function copy(from, to) {
  fs.mkdirSync(to, { recursive: true });
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    if (excluded.has(entry.name) || entry.name === 'start.sh' || entry.name === 'capture.sh' || entry.name === 'startup.sh') continue;
    const src = path.join(from, entry.name);
    const dst = path.join(to, entry.name);
    if (path.resolve(src) === output || path.resolve(src).startsWith(output + path.sep)) continue;
    if (entry.isDirectory()) copy(src, dst);
    else if (entry.isFile()) fs.copyFileSync(src, dst);
  }
}
copy(source, output);
NODE
  else
    echo 'package.json is present but has no build script and no root index.html.' >&2
    exit 1
  fi
else
  # This repository has no package manifest or web entry point. Build a small,
  # dependency-free static preview from its existing README instead of letting
  # the generic launcher fail with "No generated index.html".
  run_timed node - "$PROJECT_DIR" "$OUTPUT_DIR" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(process.argv[2]);
const out = path.resolve(process.argv[3]);
const readme = fs.existsSync(path.join(root, 'README.md'))
  ? fs.readFileSync(path.join(root, 'README.md'), 'utf8')
  : '# Project preview';
const title = (readme.match(/^#\s+(.+)$/m) || [null, 'Project preview'])[1].trim();
const esc = value => String(value).replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
const links = [...readme.matchAll(/\[[^\]]+\]\((https?:\/\/[^)]+)\)/g)].map(match => match[1]);
const projectUrl = links.find(url => url.includes('omgithub.com/') && !url.includes('?remix=')) || 'https://omgithub.com';
const sourceUrl = links.find(url => url.includes('github.com/') && !url.includes('/actions') && !url.includes('/issues')) || 'https://github.com';
const actionsUrl = links.find(url => url.endsWith('/actions')) || sourceUrl;
fs.mkdirSync(out, { recursive: true });
const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#101116"><title>${esc(title)} — Project preview</title>
  <style>
    :root{color-scheme:dark;font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#101116;color:#f5f5f7;font-synthesis:none;text-rendering:optimizeLegibility}
    *{box-sizing:border-box}body{margin:0;min-height:100vh;background:radial-gradient(ellipse at 75% 4%,#30254c 0,transparent 34%),radial-gradient(ellipse at 4% 92%,#172d37 0,transparent 32%),#101116}
    a{color:inherit;text-decoration:none}.shell{width:min(1120px,calc(100% - 48px));margin:auto}.nav{height:82px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #ffffff16}.brand{display:flex;align-items:center;gap:12px;font-weight:700;letter-spacing:.02em}.mark{width:34px;height:34px;border-radius:11px;background:linear-gradient(145deg,#b39aff,#667de8);display:grid;place-items:center;color:#15121f;font-size:17px}.nav-note{font-size:13px;color:#a6a6b3}.hero{padding:105px 0 70px;max-width:760px}.eyebrow{display:inline-flex;align-items:center;gap:9px;border:1px solid #ffffff1a;border-radius:999px;padding:8px 12px;color:#c6bddf;font-size:12px;letter-spacing:.1em;text-transform:uppercase}.dot{width:7px;height:7px;background:#a891ff;border-radius:50%;box-shadow:0 0 14px #a891ff}.hero h1{font-size:clamp(54px,9vw,96px);letter-spacing:-.075em;line-height:.96;margin:25px 0 20px}.hero p{font-size:clamp(17px,2.2vw,20px);line-height:1.65;color:#b5b4c0;max-width:640px;margin:0}.actions{display:flex;gap:12px;margin-top:34px;flex-wrap:wrap}.button{display:inline-flex;align-items:center;justify-content:center;min-height:48px;padding:0 19px;border-radius:12px;font-weight:650;font-size:14px;transition:transform .18s,background .18s}.button:hover{transform:translateY(-2px)}.primary{background:#eee9ff;color:#191522}.secondary{border:1px solid #ffffff24;background:#ffffff08}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;padding-bottom:72px}.card{border:1px solid #ffffff17;background:linear-gradient(145deg,#ffffff0c,#ffffff04);border-radius:18px;padding:22px;min-height:150px}.card small{color:#aaa7b7;text-transform:uppercase;letter-spacing:.12em;font-size:10px}.card h2{font-size:18px;margin:18px 0 7px;letter-spacing:-.02em}.card p{color:#a6a5b1;line-height:1.5;font-size:13px;margin:0}.foot{border-top:1px solid #ffffff16;padding:19px 0 28px;color:#858490;font-size:12px;display:flex;justify-content:space-between;gap:12px}.foot a{color:#c6bddf}@media(max-width:680px){.shell{width:min(100% - 36px,520px)}.nav{height:68px}.hero{padding:78px 0 53px}.hero h1{font-size:62px}.cards{grid-template-columns:1fr;padding-bottom:50px}.card{min-height:125px}.foot{flex-direction:column}}
  </style>
</head>
<body>
  <div class="shell">
    <header class="nav"><a class="brand" href="${esc(projectUrl)}"><span class="mark" aria-hidden="true">${esc(title.slice(0,1).toUpperCase())}</span><span>${esc(title)}</span></a><span class="nav-note">A project preview</span></header>
    <main>
      <section class="hero"><span class="eyebrow"><span class="dot"></span> Built from this repository</span><h1>${esc(title)}<br>starts here.</h1><p>A clean preview for this project workspace. Explore the source, open the project, or check its build activity.</p><div class="actions"><a class="button primary" href="${esc(projectUrl)}">Open the project <span aria-hidden="true">&nbsp;↗</span></a><a class="button secondary" href="${esc(sourceUrl)}">Explore source</a></div></section>
      <section class="cards" aria-label="Project links"><a class="card" href="${esc(projectUrl)}"><small>01 / Workspace</small><h2>Open the project ↗</h2><p>Launch the project page and continue exploring.</p></a><a class="card" href="${esc(sourceUrl)}"><small>02 / Source</small><h2>Read the code ↗</h2><p>Browse the repository and its project history.</p></a><a class="card" href="${esc(actionsUrl)}"><small>03 / Builds</small><h2>Build activity ↗</h2><p>See recent automation and validation runs.</p></a></section>
    </main>
    <footer class="foot"><span>${esc(title)} · Project preview</span><a href="${esc(sourceUrl)}">Source repository ↗</a></footer>
  </div>
</body>
</html>`;
fs.writeFileSync(path.join(out, 'index.html'), html);
NODE
fi

if [[ ! -f "$OUTPUT_DIR/index.html" ]]; then
  echo "Static build output missing: $OUTPUT_DIR/index.html" >&2
  exit 1
fi

run_timed node - "$PROJECT_DIR" "$OUTPUT_DIR" "$DEPLOYMENT_FILE" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const [project, directory, file] = process.argv.slice(2).map(value => path.resolve(value));
fs.mkdirSync(path.dirname(file), { recursive: true });
fs.writeFileSync(file, JSON.stringify({ project, directory }, null, 2) + '\n');
NODE

# The server remains in the foreground for the controller-owned tmux session.
# For generated static output, invoke the runtime server from dist so it serves
# the built directory and does not rewrite the worker's project metadata.
if [[ -f "$PROJECT_DIR/package.json" ]]; then
  cd "$PROJECT_DIR"
  run_timed node "$RUNTIME_DIR/scripts/default-start.mjs"
else
  cd "$OUTPUT_DIR"
  run_timed env -u OPENCODE_WEB_DIR node "$RUNTIME_DIR/scripts/default-start.mjs"
fi
