#!/usr/bin/env node

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const scriptPath = path.join(__dirname, '..', 'scripts', 'squash-only.sh');

// Check if script exists
if (!fs.existsSync(scriptPath)) {
  console.error(`❌ Error: Script not found at ${scriptPath}`);
  process.exit(1);
}

// Get all arguments except node and script name
const args = process.argv.slice(2);

// Spawn the bash script with all arguments
const child = spawn('bash', [scriptPath, ...args], {
  stdio: 'inherit',
  cwd: path.join(__dirname, '..'),
});

let isExiting = false;

// Handle termination signals (Ctrl-C, etc.)
const handleSignal = (signal) => {
  if (isExiting) {
    return;
  }
  isExiting = true;
  
  // Forward the signal to the child process
  if (child && !child.killed) {
    child.kill(signal);
  }
};

process.on('SIGINT', handleSignal);
process.on('SIGTERM', handleSignal);

// Cleanup on process exit
process.on('exit', () => {
  if (child && !child.killed) {
    child.kill('SIGTERM');
  }
});

child.on('error', (error) => {
  console.error(`❌ Error executing script: ${error.message}`);
  process.exit(1);
});

child.on('exit', (code, signal) => {
  // If child was killed by a signal, exit with appropriate code
  if (signal) {
    process.exit(signal === 'SIGINT' ? 130 : 143);
  } else {
    process.exit(code || 0);
  }
});

