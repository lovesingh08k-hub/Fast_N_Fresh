const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const root = path.join(__dirname, '..', 'src');
const files = [];

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (entry.isFile() && full.endsWith('.js')) files.push(full);
  }
}

walk(root);
let failed = 0;
for (const file of files.sort()) {
  try {
    execFileSync(process.execPath, ['--check', file], { stdio: 'pipe' });
  } catch (err) {
    failed += 1;
    process.stderr.write(`
Syntax error: ${path.relative(process.cwd(), file)}
`);
    process.stderr.write(err.stderr?.toString() || err.message);
  }
}

if (failed) {
  console.error(`\n${failed} JavaScript file(s) failed syntax validation.`);
  process.exit(1);
}

console.log(`Backend syntax check passed: ${files.length} JavaScript file(s).`);
