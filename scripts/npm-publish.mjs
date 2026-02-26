#!/usr/bin/env node
import { execSync } from "node:child_process";
import { exit } from "node:process";

/**
 * Publish script that checks npm login status before publishing
 */

function checkNpmLogin() {
  try {
    const username = execSync("npm whoami", {
      encoding: "utf8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    console.log(`✓ Logged in to npm as: ${username}`);
    return true;
  } catch {
    console.error("✗ You are not logged in to npm.");
    console.error("\nPlease run: npm login");
    console.error("\nThen try publishing again.");
    return false;
  }
}

function buildPackage() {
  console.log("\n📦 Building package...");
  try {
    execSync("pnpm build", { stdio: "inherit" });
    console.log("✓ Build completed successfully");
    return true;
  } catch {
    console.error("✗ Build failed");
    return false;
  }
}

function publishPackage() {
  console.log("\n🚀 Publishing package...");
  try {
    execSync("npm publish --access public", { stdio: "inherit" });
    console.log("\n✓ Package published successfully!");
    console.log("\nUsers can now install it with:");
    console.log("  npm install -g @cukaspodolskii/hanaclaw");
    return true;
  } catch {
    console.error("\n✗ Publish failed");
    return false;
  }
}

async function main() {
  console.log("🔍 Checking npm login status...");

  if (!checkNpmLogin()) {
    exit(1);
  }

  if (!buildPackage()) {
    exit(1);
  }

  if (!publishPackage()) {
    exit(1);
  }

  console.log("\n🎉 All done!");
}

main().catch((error) => {
  console.error("Error:", error);
  exit(1);
});
