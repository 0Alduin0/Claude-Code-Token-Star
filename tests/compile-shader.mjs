import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const loadGlslang = require('@webgpu/glslang');

const here = path.dirname(fileURLToPath(import.meta.url));
const body = fs.readFileSync(path.join(here, '..', 'supernova.glsl'), 'utf8');
const header = `#version 310 es
precision highp float;
precision highp int;
layout(set=0,binding=0) uniform Params {
  vec3 resolution;
  float time;
  float cursorTime;
  vec4 currentColor;
  vec4 previousColor;
  vec4 mouse;
} u;
#define iResolution u.resolution
#define iTime u.time
#define iTimeCursorChange u.cursorTime
#define iCurrentCursorColor u.currentColor
#define iPreviousCursorColor u.previousColor
#define iMouse u.mouse
layout(set=0,binding=1) uniform sampler2D iChannel0;
layout(location=0) out vec4 outColor;
`;
const footer = `
void main() {
  mainImage(outColor, gl_FragCoord.xy);
}
`;

loadGlslang().then((glslang) => {
  glslang.compileGLSL(header + body + footer, 'fragment');
  console.log('supernova.glsl: GLSL syntax OK');
  process.exit(0);
}).catch((error) => {
  console.error(error);
  process.exit(1);
});
