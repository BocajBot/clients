const path = require("path");
const { buildConfig } = require("./webpack.base");

module.exports = (webpackConfig, context) => {
  // Detect if called by Nx (context parameter exists)
  const isNxBuild = context && context.options;

  if (isNxBuild) {
    // Nx build configuration
    const contextEnv = context.options.env ?? {};
    Object.keys(contextEnv).forEach((key) => {
      process.env[key] = contextEnv[key];
    });

    const mode = context.options.mode || "development";
    if (process.env.NODE_ENV == null) {
      process.env.NODE_ENV = mode;
    }
    const ENV = (process.env.ENV = contextEnv.ENV ?? contextEnv.NODE_ENV ?? mode);

    return buildConfig({
      configName: "OSS",
      configFile: __filename,
      popup: {
        entry: path.resolve(__dirname, "src/popup/main.ts"),
        entryModule: "src/popup/app.module#AppModule",
      },
      background: {
        entry: path.resolve(__dirname, "src/platform/background.ts"),
        tsConfig: path.resolve(__dirname, "tsconfig.background.json"),
      },
      tsConfig: path.resolve(__dirname, "tsconfig.build.json"),
      mv2TsConfig: path.resolve(__dirname, "tsconfig.build.mv2.json"),
      outputPath:
        context.context && context.context.root
          ? path.resolve(context.context.root, context.options.outputPath)
          : context.options.outputPath,
      mode: mode,
      env: ENV,
    });
  } else {
    // npm build configuration
    return buildConfig({
      configName: "OSS",
      configFile: __filename,
      popup: {
        entry: path.resolve(__dirname, "src/popup/main.ts"),
        entryModule: "src/popup/app.module#AppModule",
      },
      background: {
        entry: path.resolve(__dirname, "src/platform/background.ts"),
        tsConfig: path.resolve(__dirname, "tsconfig.background.json"),
      },
      tsConfig: path.resolve(__dirname, "tsconfig.build.json"),
      mv2TsConfig: path.resolve(__dirname, "tsconfig.build.mv2.json"),
    });
  }
};
