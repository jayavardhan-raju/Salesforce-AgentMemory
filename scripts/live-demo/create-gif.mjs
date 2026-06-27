import { spawn } from "node:child_process";
import { copyFile, mkdir, readdir, rm, stat } from "node:fs/promises";
import { basename, join } from "node:path";
import { tmpdir } from "node:os";

// Stitch the Playwright walkthrough screenshots into a single demo GIF with
// ffmpeg. Frames are ordered by filename (the UI runner prefixes them), held
// ~2s each, and padded onto a white 1280x720 canvas. Best-effort: if there are
// no screenshots (UI step skipped/failed), it exits cleanly without a GIF.

const [screenshotsDir, outputPath] = process.argv.slice(2);

if (!screenshotsDir || !outputPath) {
  throw new Error("Usage: node create-gif.mjs <screenshots-dir> <output.gif>");
}

let files = [];
try {
  files = (await readdir(screenshotsDir))
    .filter((file) => file.toLowerCase().endsWith(".png"))
    .sort()
    .map((file) => join(screenshotsDir, file));
} catch {
  console.log(`No screenshots directory at ${screenshotsDir}; skipping GIF generation`);
  process.exit(0);
}

if (files.length === 0) {
  console.log("No screenshots found; skipping GIF generation");
  process.exit(0);
}

const frameDir = join(tmpdir(), `agentmemory-gif-${Date.now()}`);
await mkdir(frameDir, { recursive: true });

// Verify ffmpeg availability early so we fail fast and log a clear message.
try {
  // run() is declared later as a function declaration and is hoisted.
  await run("ffmpeg", ["-version"]);
} catch (err) {
  console.warn("ffmpeg is not available or not executable; skipping GIF generation");
  await rm(frameDir, { recursive: true, force: true });
  process.exit(0);
}

try {
  for (const [index, file] of files.entries()) {
    await copyFile(file, join(frameDir, `frame-${String(index + 1).padStart(4, "0")}.png`));
  }

  await run("ffmpeg", [
    "-y",
    "-framerate",
    "0.5",
    "-i",
    join(frameDir, "frame-%04d.png"),
    "-vf",
    "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=white,fps=2",
    "-loop",
    "0",
    outputPath,
  ]);

  const output = await stat(outputPath);
  console.log(`Created ${basename(outputPath)} from ${files.length} screenshot(s) (${output.size} bytes)`);
} catch (error) {
  // Do not fail the run if ffmpeg is unavailable or errors; the email still goes out.
  console.warn(`GIF generation failed (continuing without it): ${error.message}`);
} finally {
  await rm(frameDir, { recursive: true, force: true });
}

async function run(command, args) {
  await new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: "inherit" });
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${command} exited with code ${code}`));
      }
    });
  });
}
