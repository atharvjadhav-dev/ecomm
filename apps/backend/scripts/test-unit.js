const { spawnSync } = require("child_process");
const path = require("path");

const env = {
  ...process.env,
  TEST_TYPE: "unit",
  NODE_OPTIONS: [process.env.NODE_OPTIONS, "--experimental-vm-modules"]
    .filter(Boolean)
    .join(" "),
};

const jestBin = path.resolve(
  __dirname,
  "../../../node_modules/jest/bin/jest.js"
);

const result = spawnSync(
  process.execPath,
  [jestBin, "--silent", "--runInBand", "--forceExit", ...process.argv.slice(2)],
  {
    stdio: "inherit",
    cwd: path.resolve(__dirname, ".."),
    env,
  }
);

process.exit(result.status ?? 1);
