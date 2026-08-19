const canvas = document.querySelector("#view");
const ctx = canvas.getContext("2d", { alpha: false });
const slider = document.querySelector("#level");
const stageOut = document.querySelector("#stage");
const massOut = document.querySelector("#mass");
const rendererOut = document.querySelector("#renderer");
const errorOut = document.querySelector("#error");

if (!ctx) {
  const message = "Canvas 2D is required.";
  errorOut.textContent = message;
  throw new Error(message);
}

const TAU = Math.PI * 2;
const stages = [
  { limit: 0.15, name: "RED DWARF", slug: "red-dwarf", anchor: 0.07, clearance: 180 },
  { limit: 0.35, name: "MAIN SEQUENCE", slug: "main-sequence", anchor: 0.25, clearance: 250 },
  { limit: 0.55, name: "BLUE GIANT", slug: "blue-giant", anchor: 0.45, clearance: 340 },
  { limit: 0.75, name: "HYPERGIANT", slug: "hypergiant", anchor: 0.65, clearance: 360 },
  { limit: 0.90, name: "NEUTRON STAR", slug: "neutron-star", anchor: 0.82, clearance: 230 },
  { limit: 1.01, name: "QUASAR", slug: "quasar", anchor: 0.95, clearance: 200 },
];
const checkpoints = stages.map((stage) => [Math.round(stage.anchor * 100), stage.name
  .toLowerCase()
  .replace(/(^|\s)\S/g, (letter) => letter.toUpperCase())]);
const stageFor = (level) => stages.find(({ limit }) => level < limit);
const fract = (value) => value - Math.floor(value);
const seeded = (index, salt = 0) => fract(Math.sin(index * 91.713 + salt * 47.17) * 43758.5453);
const backgroundStars = Array.from({ length: 42 }, (_, index) => ({
  x: seeded(index, 1) * canvas.width,
  y: seeded(index, 2) * canvas.height,
  r: 0.45 + seeded(index, 3) * 1.25,
  phase: seeded(index, 4) * TAU,
}));

let touring = false;
let tourStart = 0;
let dragging = false;
let manualPosition = null;

function roundedRect(context, x, y, width, height, radius) {
  const r = Math.min(radius, width / 2, height / 2);
  context.beginPath();
  context.moveTo(x + r, y);
  context.arcTo(x + width, y, x + width, y + height, r);
  context.arcTo(x + width, y + height, x, y + height, r);
  context.arcTo(x, y + height, x, y, r);
  context.arcTo(x, y, x + width, y, r);
  context.closePath();
}

function loadImage(url) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.decoding = "async";
    image.addEventListener("load", () => resolve(image), { once: true });
    image.addEventListener("error", () => reject(new Error(`Could not load ${url}`)), { once: true });
    image.src = url;
  });
}

async function loadStageAsset(stage) {
  const candidates = [
    `./preview-${stage.slug}.webp`,
    `../assets/preview/overlay-${stage.slug}.webp`,
  ];
  let lastError;
  for (const url of candidates) {
    try {
      stage.image = await loadImage(url);
      return;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

function drawTerminal(time) {
  const background = ctx.createLinearGradient(0, 0, canvas.width, canvas.height);
  background.addColorStop(0, "#07101a");
  background.addColorStop(1, "#04080e");
  ctx.fillStyle = background;
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  ctx.font = "20px Consolas, monospace";
  const rows = [
    "$ claude", "", "  Reading the repository and tracing the render pipeline...",
    "  Editing src/renderer/generic.zig", "  Running tests  [##################--]  91%", "",
    "  The terminal remains readable while stellar mass accumulates.", "", "  > _",
  ];
  rows.forEach((text, index) => {
    ctx.fillStyle = index === 0 ? "#84d6a0" : index === 8 ? "#b7c9dc" : "#6f879e";
    ctx.fillText(text, 34, 50 + index * 42);
  });

  for (const star of backgroundStars) {
    ctx.globalAlpha = 0.20 + 0.38 * (0.5 + 0.5 * Math.sin(time * 1.7 + star.phase));
    ctx.fillStyle = "#8fd8ff";
    ctx.beginPath();
    ctx.arc(star.x, star.y, star.r, 0, TAU);
    ctx.fill();
  }
  ctx.globalAlpha = 1;
}

function drawMassPanel(x, y, tokens) {
  const label = `MASS ${Math.round(tokens / 1000)}K / 200K`;
  ctx.font = "600 15px 'Segoe UI', sans-serif";
  const labelWidth = ctx.measureText(label).width;
  const rate = " | 5H 61% | 2h 23m";
  ctx.font = "12px 'Segoe UI', sans-serif";
  const rateWidth = ctx.measureText(rate).width;
  const width = labelWidth + rateWidth + 49;
  const left = Math.max(8, Math.min(canvas.width - width - 8, x - width / 2));
  const top = Math.max(8, Math.min(canvas.height - 42, y));

  ctx.save();
  roundedRect(ctx, left, top, width, 34, 7);
  ctx.fillStyle = "rgba(10,17,27,.95)";
  ctx.fill();
  ctx.strokeStyle = "rgba(95,145,191,.85)";
  ctx.lineWidth = 1;
  ctx.stroke();
  ctx.font = "600 15px 'Segoe UI', sans-serif";
  ctx.fillStyle = "#f8fcff";
  ctx.fillText(label, left + 9, top + 22);
  ctx.font = "12px 'Segoe UI', sans-serif";
  ctx.fillStyle = "#a9c4df";
  ctx.fillText(rate, left + 9 + labelWidth, top + 22);
  ctx.fillStyle = "#14283b";
  ctx.fillRect(left + width - 29, top + 1, 28, 32);
  ctx.fillStyle = "#ffffff";
  ctx.fillText("▼", left + width - 21, top + 22);
  ctx.restore();
}

function drawOverlay(level) {
  const stage = stageFor(level);
  const position = manualPosition ?? { x: canvas.width * 0.70, y: canvas.height * 0.36 };
  const x = Math.max(0, Math.min(canvas.width, position.x));
  const y = Math.max(0, Math.min(canvas.height, position.y));
  const displayScale = 0.65 + 0.35 * level;
  const anchorScale = 0.65 + 0.35 * stage.anchor;
  const relativeScale = displayScale / anchorScale;

  if (stage.image) {
    const width = 700 * relativeScale;
    const height = 700 * relativeScale;
    ctx.drawImage(
      stage.image,
      x - 350 * relativeScale,
      y - 260 * relativeScale,
      width,
      height,
    );
  }
  drawMassPanel(x, y + stage.clearance * displayScale + 12, level * 200000);
}

const requestedLevel = Number(new URLSearchParams(location.search).get("level"));
if (Number.isFinite(requestedLevel)) slider.value = String(Math.max(0, Math.min(100, requestedLevel)));

const usageToggle = document.querySelector("#usage-toggle");
const usageDetails = document.querySelector("#usage-details");
const usageArrow = document.querySelector("#usage-arrow");
usageToggle.addEventListener("click", () => {
  const open = usageToggle.getAttribute("aria-expanded") !== "true";
  usageToggle.setAttribute("aria-expanded", String(open));
  usageDetails.hidden = !open;
  usageArrow.textContent = open ? "▲" : "▼";
});

const stageButtons = checkpoints.map(([value, label]) => {
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = label;
  button.dataset.level = value;
  button.addEventListener("click", () => {
    touring = false;
    document.querySelector("#tour").textContent = "Auto tour";
    slider.value = String(value);
  });
  document.querySelector("#stages").append(button);
  return button;
});

document.querySelector("#tour").addEventListener("click", (event) => {
  touring = !touring;
  tourStart = performance.now();
  event.currentTarget.textContent = touring ? "Stop tour" : "Auto tour";
});

document.querySelector("#capture").addEventListener("click", () => {
  const level = Number(slider.value);
  canvas.toBlob((blob) => {
    if (!blob) return;
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `claude-token-star-${String(level).replace(".", "_")}.png`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(link.href), 1000);
  }, "image/png");
});

function placeAtPointer(event) {
  const bounds = canvas.getBoundingClientRect();
  manualPosition = {
    x: (event.clientX - bounds.left) * canvas.width / bounds.width,
    y: (event.clientY - bounds.top) * canvas.height / bounds.height,
  };
}

canvas.addEventListener("pointerdown", (event) => {
  dragging = true;
  canvas.classList.add("dragging");
  canvas.setPointerCapture(event.pointerId);
  placeAtPointer(event);
});
canvas.addEventListener("pointermove", (event) => {
  if (dragging) placeAtPointer(event);
});
canvas.addEventListener("pointerup", (event) => {
  dragging = false;
  canvas.classList.remove("dragging");
  canvas.releasePointerCapture(event.pointerId);
});
canvas.addEventListener("pointercancel", () => {
  dragging = false;
  canvas.classList.remove("dragging");
});
document.querySelector("#reset-position").addEventListener("click", () => { manualPosition = null; });

function frame(now) {
  if (touring) slider.value = String(((now - tourStart) / 350) % 101);
  const level = Number(slider.value) / 100;
  const tokens = Math.round(level * 200000);
  const stage = stageFor(level);
  stageOut.textContent = `${Math.round(level * 100)}% · ${stage.name}`;
  massOut.textContent = `MASS ${Math.round(tokens / 1000)}K / 200K`;
  stageButtons.forEach((button) => button.classList.toggle(
    "active", stageFor(Number(button.dataset.level) / 100).name === stage.name,
  ));
  drawTerminal(now / 1000);
  drawOverlay(level);
  requestAnimationFrame(frame);
}

try {
  await Promise.all(stages.map(loadStageAsset));
  rendererOut.textContent = "WPF ASSETS READY";
  rendererOut.className = "ok";
  requestAnimationFrame(frame);
} catch (error) {
  rendererOut.textContent = "ASSET ERROR";
  errorOut.textContent = error.message;
  throw error;
}
