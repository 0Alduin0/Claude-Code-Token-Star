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
  { limit: 0.15, name: "RED DWARF", diameter: 68, hot: "#ff7a32", cool: "#6d0702", accent: "#3b0000" },
  { limit: 0.35, name: "MAIN SEQUENCE", diameter: 96, hot: "#ffe89a", cool: "#d95a09", accent: "#ff8a16" },
  { limit: 0.55, name: "BLUE GIANT", diameter: 128, hot: "#e9f7ff", cool: "#2768c7", accent: "#4b8ee8" },
  { limit: 0.75, name: "HYPERGIANT", diameter: 158, hot: "#ffffd8", cool: "#ff8e18", accent: "#ff9a14" },
  { limit: 0.90, name: "NEUTRON STAR", diameter: 42, hot: "#ffffff", cool: "#2b78d4", accent: "#4f9eff" },
  { limit: 1.01, name: "QUASAR", diameter: 92, hot: "#000000", cool: "#000000", accent: "#ff6b26" },
];
const checkpoints = [
  [7, "Red dwarf"], [25, "Main sequence"], [45, "Blue giant"],
  [65, "Hypergiant"], [82, "Neutron star"], [95, "Quasar"],
];
const stageFor = (level) => stages.find(({ limit }) => level < limit);
const fract = (value) => value - Math.floor(value);
const seeded = (index, salt = 0) => fract(Math.sin(index * 91.713 + salt * 47.17) * 43758.5453);

const backgroundStars = Array.from({ length: 42 }, (_, index) => ({
  x: seeded(index, 1) * canvas.width,
  y: seeded(index, 2) * canvas.height,
  r: 0.45 + seeded(index, 3) * 1.25,
  phase: seeded(index, 4) * TAU,
}));
const surfaceSeeds = Array.from({ length: 14 }, (_, index) => ({
  angle: seeded(index, 5) * TAU,
  radius: 0.20 + seeded(index, 6) * 0.72,
  size: 2 + seeded(index, 7) * 6,
  speed: (index % 2 ? -1 : 1) * (0.13 + seeded(index, 8) * 0.22),
  phase: seeded(index, 9) * TAU,
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

function drawEllipseStroke(x, y, rx, ry, rotation, color, width, alpha = 1, dash = [], offset = 0, blur = 0, start = 0, end = TAU) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(rotation);
  ctx.globalAlpha = alpha;
  if (typeof color === "string") {
    ctx.strokeStyle = color;
  } else {
    const gradient = ctx.createLinearGradient(-rx, 0, rx, 0);
    color.forEach(([stop, value]) => gradient.addColorStop(stop, value));
    ctx.strokeStyle = gradient;
  }
  ctx.lineWidth = width;
  ctx.setLineDash(dash);
  ctx.lineDashOffset = offset;
  ctx.shadowColor = color;
  ctx.shadowBlur = blur;
  ctx.beginPath();
  ctx.ellipse(0, 0, rx, ry, 0, start, end);
  ctx.stroke();
  ctx.restore();
}

function drawRadialDisc(x, y, radius, inner, outer, alpha = 1, blur = 0) {
  const gradient = ctx.createRadialGradient(x - radius * 0.22, y - radius * 0.24, radius * 0.05, x, y, radius);
  gradient.addColorStop(0, "#ffffff");
  gradient.addColorStop(0.18, inner);
  gradient.addColorStop(1, outer);
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.fillStyle = gradient;
  ctx.shadowColor = inner;
  ctx.shadowBlur = blur;
  ctx.beginPath();
  ctx.arc(x, y, radius, 0, TAU);
  ctx.fill();
  ctx.restore();
}

function drawCorona(x, y, radius, phase, turbulence, color, alpha, blur) {
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.fillStyle = color;
  ctx.strokeStyle = color;
  ctx.lineWidth = 1;
  ctx.shadowColor = color;
  ctx.shadowBlur = blur;
  ctx.beginPath();
  for (let index = 0; index < 28; index += 1) {
    const angle = TAU * index / 28;
    const noise = 0.52 * Math.sin(angle * 11 + phase)
      + 0.31 * Math.sin(angle * 19 - phase * 1.7)
      + 0.17 * Math.sin(angle * 31 + phase * 0.63);
    const cardinal = Math.abs(Math.cos(angle * 2)) ** 18;
    const pointRadius = radius * (1 + turbulence * noise + turbulence * 1.7 * cardinal);
    const px = x + Math.cos(angle) * pointRadius;
    const py = y + Math.sin(angle) * pointRadius;
    if (index === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
  }
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  ctx.restore();
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

function drawParticles(stage, x, y, diameter, level, time, neutronAngle = 0) {
  for (let index = 0; index < 28; index += 1) {
    let px;
    let py;
    let alpha;
    let color = stage.hot;
    if (stage.name === "QUASAR") {
      if (index < 21) {
        const direction = index % 2 === 0 ? 1 : -1;
        const angle = index * 2.39996 + direction * time * (12 + index % 6);
        const radius = 76 + index % 9 * 11;
        const x0 = Math.cos(angle) * radius;
        const y0 = Math.sin(angle) * (13 + index % 5 * 2.8);
        const tilt = -12 * Math.PI / 180;
        px = x + x0 * Math.cos(tilt) - y0 * Math.sin(tilt);
        py = y + x0 * Math.sin(tilt) + y0 * Math.cos(tilt);
        color = index % 3 === 0 ? "#ffffff" : index % 3 === 1 ? "#ff69e8" : "#ff8d2f";
        alpha = 0.42 + 0.55 * (0.5 + 0.5 * Math.sin(time * 13 + index));
      } else {
        const travel = fract(time * 1.9 + (index - 21) / 7);
        const distance = (travel - 0.5) * 350;
        const axis = -102 * Math.PI / 180;
        const jitter = Math.sin(time * 22 + index) * (4 + 8 * Math.abs(travel - 0.5));
        px = x + Math.cos(axis) * distance - Math.sin(axis) * jitter;
        py = y + Math.sin(axis) * distance + Math.cos(axis) * jitter;
        color = "#ffffff";
        alpha = 0.34 + 0.64 * Math.sin(Math.PI * travel);
      }
    } else if (stage.name === "NEUTRON STAR") {
      const travel = fract(time * (1.8 + index % 4 * 0.13) + index / 28);
      const distance = (travel - 0.5) * 390;
      const jitter = Math.sin(time * 18 + index) * 2.5;
      px = x + Math.cos(neutronAngle) * distance - Math.sin(neutronAngle) * jitter;
      py = y + Math.sin(neutronAngle) * distance + Math.cos(neutronAngle) * jitter;
      color = "#ffffff";
      alpha = 0.28 + 0.70 * Math.sin(Math.PI * travel);
    } else {
      const travel = fract(time * (0.16 + index % 5 * 0.018) + index * 0.6180339);
      const angle = index * 2.39996 + time * (0.16 + level * 0.25);
      const radius = diameter * (0.50 + 1.85 * travel);
      px = x + Math.cos(angle) * radius;
      py = y + Math.sin(angle) * radius;
      alpha = (1 - travel) * (0.38 + 0.55 * level);
    }
    ctx.save();
    ctx.globalAlpha = Math.max(0, alpha);
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(px, py, 1.2 + index % 5 * 0.55, 0, TAU);
    ctx.fill();
    ctx.restore();
  }
}

function drawNormalStar(stage, x, y, diameter, level, time) {
  const radius = diameter / 2;
  const pulse = 0.5 + 0.5 * Math.sin(time * 2.6);

  drawRadialDisc(x, y, diameter * 2.1, stage.hot, "rgba(0,0,0,0)", 0.20 + 0.08 * Math.sin(time * 1.7), 10);
  drawEllipseStroke(x, y, diameter * (0.86 + 0.10 * pulse), diameter * (0.86 + 0.10 * pulse), 0, stage.hot, 3, (0.18 + 0.22 * level) * pulse, [], 0, 3);
  drawEllipseStroke(x, y, diameter * (0.65 + 0.06 * pulse), diameter * (0.65 + 0.06 * pulse), 0, stage.hot, 2, (0.30 + 0.24 * level) * (1 - pulse), [], 0, 2);

  const rayRadius = diameter * 0.52;
  for (let index = 0; index < 16; index += 1) {
    const angle = (index * 360 / 16 + time * (8 + level * 18)) * Math.PI / 180;
    const inner = rayRadius * 0.84;
    const gain = index % 12 === 0 ? 3.8 + 1.3 * level : index % 4 === 0 ? 2 + 0.8 * level : 1.25 + 0.75 * level;
    const outer = rayRadius * (gain + 0.42 * Math.sin(time * 2.1 + index * 1.7));
    ctx.save();
    ctx.globalAlpha = index % 12 === 0 ? 0.68 : index % 4 === 0 ? 0.46 : 0.22 + 0.30 * level;
    ctx.strokeStyle = stage.hot;
    ctx.lineWidth = index % 12 === 0 ? 3.2 : index % 4 === 0 ? 1.8 : 0.9;
    ctx.beginPath();
    ctx.moveTo(x + Math.cos(angle) * inner, y + Math.sin(angle) * inner);
    ctx.lineTo(x + Math.cos(angle) * outer, y + Math.sin(angle) * outer);
    ctx.stroke();
    ctx.restore();
  }

  drawParticles(stage, x, y, diameter, level, time);
  if (stage.name === "HYPERGIANT") {
    drawEllipseStroke(x, y, diameter * 0.925, diameter * 0.925, 0, "#ffb52e", 3, 0.62, [], 0, 4);
    drawEllipseStroke(x, y, diameter * 0.71, diameter * 0.71, 0, "#ffe47a", 4, 0.88, [], 0, 3);
  }

  drawCorona(x, y, radius * 2.18, time * 0.72, 0.18 + 0.10 * level, stage.hot, 0.18 + 0.12 * level, 5);
  drawCorona(x, y, radius * 1.48, -time * 1.08, 0.13 + 0.08 * level, stage.hot, 0.30 + 0.16 * level, 3);
  drawRadialDisc(x, y, diameter * 1.375, stage.hot, "rgba(0,0,0,0)", 0.46, 12);

  for (let index = 0; index < 3; index += 1) {
    const width = diameter * (1.16 + index * 0.10);
    const height = width * (0.54 + 0.055 * (index % 4));
    const angle = (index * 37 + time * (index % 2 === 0 ? 9 : -6)) * Math.PI / 180;
    drawEllipseStroke(x, y, width / 2, height / 2, angle, stage.hot, 1.4 + index % 3 * 0.8, 0.16 + 0.055 * index + (stage.name === "HYPERGIANT" ? 0.18 : 0), [5, 3], time * (index % 2 === 0 ? 3.5 : -2.8));
  }

  drawRadialDisc(x, y, radius, stage.hot, stage.cool, 1, 4);
  for (let index = 0; index < 6; index += 1) {
    const width = diameter * (0.25 + index * 0.039);
    const height = width * (0.18 + 0.055 * (index % 5));
    const angle = (index * 41 + time * (index % 2 === 0 ? 13 : -9)) * Math.PI / 180;
    const color = index % 4 === 0 ? "#ffffff" : index % 3 === 0 ? stage.accent : stage.hot;
    drawEllipseStroke(x, y, width / 2, height / 2, angle, color, 0.8 + index % 4 * 0.55, 0.11 + 0.025 * index, [4, 3], time * (index % 2 === 0 ? 7 : -5) + index);
  }
  surfaceSeeds.forEach((seed, index) => {
    const angle = seed.angle + time * seed.speed;
    const dotRadius = diameter * 0.43 * seed.radius;
    ctx.save();
    ctx.globalAlpha = 0.07 + 0.24 * (0.5 + 0.5 * Math.sin(time * 1.7 + seed.phase));
    ctx.fillStyle = index % 7 === 0 ? "#ffffff" : index % 3 === 0 ? stage.accent : stage.hot;
    ctx.beginPath();
    ctx.arc(x + Math.cos(angle) * dotRadius, y + Math.sin(angle) * dotRadius, seed.size / 2, 0, TAU);
    ctx.fill();
    ctx.restore();
  });
}

function drawRotatedBeam(x, y, width, height, angle, fill, alpha, blur, radius = height / 2) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(angle);
  ctx.globalAlpha = alpha;
  if (typeof fill === "string") {
    ctx.fillStyle = fill;
  } else {
    const horizontal = fill.direction === "horizontal";
    const gradient = ctx.createLinearGradient(
      horizontal ? -width / 2 : 0,
      horizontal ? 0 : -height / 2,
      horizontal ? width / 2 : 0,
      horizontal ? 0 : height / 2,
    );
    fill.stops.forEach(([stop, value]) => gradient.addColorStop(stop, value));
    ctx.fillStyle = gradient;
  }
  ctx.shadowColor = typeof fill === "string" ? fill : "#ffffff";
  ctx.shadowBlur = blur;
  roundedRect(ctx, -width / 2, -height / 2, width, height, radius);
  ctx.fill();
  ctx.restore();
}

function drawNeutronStar(stage, x, y, diameter, level, time) {
  const angle = fract(time * 10 / TAU) * TAU;
  drawRadialDisc(x, y, diameter * 3.4, stage.hot, "rgba(0,0,0,0)", 0.32, 12);
  drawParticles(stage, x, y, diameter, level, time, angle);

  const aura = { direction: "horizontal", stops: [
    [0, "rgba(71,142,255,0)"], [0.26, "rgba(90,184,255,.6)"],
    [0.5, "rgba(234,255,255,.93)"], [0.74, "rgba(90,184,255,.6)"],
    [1, "rgba(71,142,255,0)"],
  ] };
  drawRotatedBeam(x, y, 410, 66, angle, aura, 0.46 + 0.18 * Math.sin(time * 16), 10, 30);
  drawRotatedBeam(x, y, 390, 34, angle, "#4aa8ff", 0.66, 8, 15);
  drawRotatedBeam(x, y, 382, 7, angle, "#eaffff", 0.93, 3, 3);
  drawRotatedBeam(x, y, 372, 2, angle, "#ffffff", 1, 1, 1);

  for (let index = 0; index < 3; index += 1) {
    const width = 102 + index * 15;
    const height = 32 + index % 4 * 13;
    const ringAngle = (index * 29 + time * (index % 2 === 0 ? 82 : -64)) * Math.PI / 180;
    const color = index % 3 === 0 ? "#d9faff" : index % 3 === 1 ? "#4fb9ff" : "#916bff";
    drawEllipseStroke(x, y, width / 2, height / 2, ringAngle, color, 1.4 + index % 3 * 0.8, 0.30 + 0.055 * index, [5, 3], time * (index % 2 === 0 ? 18 : -15));
  }
  drawRadialDisc(x, y, diameter * 2.4, stage.hot, "rgba(0,0,0,0)", 0.64, 14);
  drawRadialDisc(x, y, diameter / 2, stage.hot, stage.cool, 1, 5);
  drawEllipseStroke(x, y, diameter / 2, diameter / 2, 0, "#ffffff", 3, 1);
}

function drawQuasar(stage, x, y, time) {
  const tilt = -12 * Math.PI / 180;
  drawParticles(stage, x, y, 92, 1, time);

  drawRotatedBeam(x, y, 94, 360, tilt, "#3968ff", 0.30 + 0.08 * Math.sin(time * 8), 0, 40);
  const jet = { direction: "vertical", stops: [
    [0, "rgba(61,115,255,0)"], [0.28, "#4f7fff"], [0.5, "#ffffff"],
    [0.72, "#4f7fff"], [1, "rgba(61,115,255,0)"],
  ] };
  drawRotatedBeam(x, y, 46, 350, tilt, jet, 0.92, 6, 18);
  drawRotatedBeam(x, y, 10, 342, tilt, "#ffffff", 0.94, 2, 5);

  const spin = time * 600 * 360;
  drawEllipseStroke(x, y, 165, 44, tilt, "#ff4724", 28, 0.50 + 0.10 * Math.sin(time * 5));
  drawEllipseStroke(x, y, 151, 36, tilt, "#ff8d2f", 4, 0.90, [1, 3, 7, 2], -spin / 18);
  drawEllipseStroke(x, y, 135, 31, tilt, "#ff6b26", 18, 0.75, [3, 1, 1, 1], -spin / 40, 4);
  const disk = [[0, "#ff2a14"], [0.24, "#ff69e8"], [0.66, "#ffffff"], [1, "#ffaf35"]];
  drawEllipseStroke(x, y, 125, 23, tilt, disk, 8, 1, [5, 1, 2, 1], spin / 24, 2);
  drawEllipseStroke(x, y, 110, 17, tilt, "#ffffff", 3, 0.93, [8, 2, 1, 2], spin / 13);

  ctx.save();
  ctx.fillStyle = "#010205";
  ctx.strokeStyle = "#ffc85a";
  ctx.lineWidth = 5;
  ctx.shadowColor = "#ff8d2f";
  ctx.shadowBlur = 6;
  ctx.beginPath();
  ctx.arc(x, y, 46, 0, TAU);
  ctx.fill();
  ctx.stroke();
  ctx.restore();

  drawEllipseStroke(x, y, 110, 17, tilt, "#ff5b2b", 17, 0.78, [5, 1, 2, 1], -spin / 24, 5, 0, Math.PI);
  drawEllipseStroke(x, y, 110, 17, tilt, disk, 8, 1, [5, 1, 2, 1], spin / 24, 1, 0, Math.PI);
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
  const top = Math.min(canvas.height - 40, y);

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

function drawOverlay(level, time) {
  const stage = stageFor(level);
  const growth = 0.65 + 0.35 * level;
  const diameter = stage.diameter * growth;
  const position = manualPosition ?? { x: canvas.width * 0.70, y: canvas.height * 0.39 };
  const x = Math.max(0, Math.min(canvas.width, position.x));
  const y = Math.max(0, Math.min(canvas.height, position.y));

  if (stage.name === "QUASAR") drawQuasar(stage, x, y, time);
  else if (stage.name === "NEUTRON STAR") drawNeutronStar(stage, x, y, diameter, level, time);
  else drawNormalStar(stage, x, y, diameter, level, time);

  const clearance = stage.name === "QUASAR" || stage.name === "NEUTRON STAR"
    ? 205
    : Math.max(82, diameter * (stage.name === "HYPERGIANT" ? 1.35 : 1.12));
  drawMassPanel(x, y + clearance, level * 200000);
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
  drawOverlay(level, now / 1000);
  requestAnimationFrame(frame);
}

rendererOut.textContent = "OVERLAY READY";
rendererOut.className = "ok";
requestAnimationFrame(frame);
