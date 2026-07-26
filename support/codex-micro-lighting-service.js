"use strict";

const dgram = require("node:dgram");

const kitPath =
  "/Applications/input.app/Contents/Resources/app.asar/" +
  "node_modules/@worklouder/wl-device-kit";
const meetingsProfileIndex = 1;
const portArgument = process.argv.indexOf("--udp-port");
const port =
  portArgument >= 0 ? Number(process.argv[portArgument + 1]) : 45931;

let communication;
let api;
let selectedProfileIndex;
let pendingSample;
let sending = false;
let closing = false;
let profileTimer;
let lastClient;
let currentStatus = "CONNECTING";
let errorGeneration = 0;

const server = dgram.createSocket("udp4");

function errorText(value) {
  if (value instanceof Error) return value.message;
  if (typeof value === "string") return value;
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function send(message, client = lastClient) {
  if (!client) return;
  const data = Buffer.from(message);
  server.send(data, client.port, client.address);
}

function reply(message, client = lastClient) {
  currentStatus = message;
  send(message, client);
}

function reportError(...values) {
  errorGeneration += 1;
  reply(`ERROR ${values.map(errorText).join(" ")}`);
}

const logger = {
  debug() {},
  info() {},
  // Other Work Louder clients share the non-exclusive HID stream. Their
  // unmatched responses are expected and are logged as warnings by the SDK.
  warn() {},
  error: reportError,
};

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function lightingConfig(sample) {
  const light = {
    effect: "solid",
    brightness: sample.brightness,
    speed: 0.5,
    magic: 1,
    color: sample.color,
  };
  return {
    backlight: { ...light },
    underglow: { ...light },
  };
}

async function drain() {
  if (
    sending ||
    !api ||
    selectedProfileIndex !== meetingsProfileIndex
  ) {
    return;
  }

  sending = true;
  try {
    while (pendingSample) {
      const sample = pendingSample;
      pendingSample = undefined;
      const errorsBeforeSend = errorGeneration;
      await api.sendLightingPreview(lightingConfig(sample));
      if (errorGeneration === errorsBeforeSend) {
        send(`APPLIED ${sample.color} ${sample.brightness}`);
      }
    }
  } finally {
    sending = false;
  }
}

async function refreshProfile() {
  if (!api || closing) return;
  try {
    const status = await api.getDeviceStatus();
    if (status.selectedProfileIndex !== selectedProfileIndex) {
      selectedProfileIndex = status.selectedProfileIndex;
      reply(`PROFILE ${selectedProfileIndex}`);
      if (selectedProfileIndex === meetingsProfileIndex) {
        void drain();
      }
    }
  } catch (error) {
    reportError(`Could not read active profile: ${errorText(error)}`);
  }
}

async function connectDevice(kit) {
  let lastConnectionError;
  for (let attempt = 1; attempt <= 8; attempt += 1) {
    const devices = new kit.WLDeviceDiscovery(logger).findWLDevices([
      kit.DeviceType.CodexMicro,
    ]);
    if (devices.length === 0) {
      lastConnectionError = new Error("Codex Micro not found");
    } else {
      communication = new kit.WLDeviceCommImpl(logger);
      try {
        await communication.connect(devices[0]);
        lastConnectionError = undefined;
        break;
      } catch (error) {
        lastConnectionError = error;
        try {
          await communication.disconnect();
        } catch {
          // A failed open may have no live handle to close.
        }
      }
    }
    await delay(500);
  }

  if (lastConnectionError) {
    throw new Error(
      `Could not connect to Codex Micro after retries: ${
        errorText(lastConnectionError)
      }`
    );
  }
}

async function close(exitCode = 0) {
  if (closing) return;
  closing = true;
  if (profileTimer) clearInterval(profileTimer);
  server.close();
  try {
    if (communication) await communication.disconnect();
  } catch {
    // The process is already exiting.
  } finally {
    process.exit(exitCode);
  }
}

server.on("message", (message, client) => {
  lastClient = client;
  try {
    const sample = JSON.parse(message.toString("utf8"));
    if (
      !Number.isInteger(sample.color) ||
      !Number.isFinite(sample.brightness) ||
      sample.brightness < 0 ||
      sample.brightness > 1
    ) {
      throw new Error("invalid color or brightness");
    }
    pendingSample = sample;
    reply(currentStatus, client);
    void drain();
  } catch (error) {
    reportError(`Invalid meter sample: ${errorText(error)}`);
  }
});

server.on("error", (error) => {
  reportError(`UDP service failed: ${errorText(error)}`);
  void close(8);
});

async function main() {
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    throw new Error("Invalid UDP port");
  }

  server.bind(port, "127.0.0.1");

  let kit;
  try {
    kit = require(kitPath);
  } catch (error) {
    throw new Error(
      `Input lighting library unavailable: ${errorText(error)}`
    );
  }

  await connectDevice(kit);
  api = new kit.WLRPCApi(communication, logger);
  reply("CONNECTED");
  await refreshProfile();
  profileTimer = setInterval(() => void refreshProfile(), 1000);
}

process.on("SIGTERM", () => void close());
process.on("SIGINT", () => void close());
process.on("uncaughtException", (error) => {
  reportError(error);
  void close(5);
});
process.on("unhandledRejection", (error) => {
  reportError(error);
  void close(6);
});

void main();
