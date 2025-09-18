#!/usr/bin/env node
const { execSync } = require("child_process");
const path = require("path");

// Grab subcommand
const args = process.argv.slice(2);
const subcommand = args[0];

const scripts = {
  deploy: "deploy.sh",
  destroy: "destroy.sh"
};

if (!subcommand || !scripts[subcommand]) {
  console.error("Unknown command or no command provided.");
  console.log("Available commands: deploy, destroy");
  process.exit(1);
}

// Path to the deploy project scripts
const scriptPath = path.join(__dirname, "..", "deploy", scripts[subcommand]);

try {
  execSync(`bash ${scriptPath}`, { stdio: "inherit" });
} catch (err) {
  console.error(`Command "${subcommand}" failed.`);
  process.exit(1);
}
