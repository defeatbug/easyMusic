// easyMusic spike bootstrap: implements the MyGo Music plugin host surface
// inside QuickJS (via flutter_js) so an unmodified plugin can run.
//
// Channels to Dart (sendMessage, provided by flutter_js):
//   'fetch'  -> async HTTP, args JSON {url, method, headers, body},
//               resolves JSON {status, headers:{lower:[values]}, body}
//   'timer'  -> resolves after N ms (args = string ms)
//   'log'    -> console output sink
//   'storageSet' / 'storageRemove' -> fire-and-forget persistence
//
// Synchronous host APIs (the desktop host is synchronous, so these must be):
//   host.storage.*  -> in-memory map seeded from __hostConfig.storage
//   host.crypto.md5 / host.crypto.aesEcbEncrypt -> pure-JS implementations
//   host.setting    -> from __hostConfig.settings

// ---------------------------------------------------------------- utilities
function __utf8Bytes(str) {
  const out = [];
  for (let i = 0; i < str.length; i++) {
    let cp = str.charCodeAt(i);
    if (cp < 0x80) { out.push(cp); continue; }
    if (cp < 0x800) { out.push(0xc0 | (cp >> 6), 0x80 | (cp & 0x3f)); continue; }
    if (cp >= 0xd800 && cp <= 0xdbff && i + 1 < str.length) {
      const lo = str.charCodeAt(i + 1);
      if (lo >= 0xdc00 && lo <= 0xdfff) {
        cp = 0x10000 + ((cp - 0xd800) * 0x400) + (lo - 0xdc00);
        i++;
        out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
        continue;
      }
    }
    out.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
  }
  return out;
}
function __bytesToHex(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += (bytes[i] >>> 4).toString(16) + (bytes[i] & 15).toString(16);
  return s;
}

// ---------------------------------------------------------------- MD5 (RFC 1321), byte-array based
function __md5Bytes(input) {
  const S = [7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
             5,9,14,20, 5,9,14,20, 5,9,14,20, 5,9,14,20,
             4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
             6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21];
  const K = [];
  for (let i = 0; i < 64; i++) K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296) >>> 0;
  const msg = input.slice();
  const bitLen = input.length * 8;
  msg.push(0x80);
  while (msg.length % 64 !== 56) msg.push(0);
  let low = bitLen >>> 0, high = Math.floor(bitLen / 4294967296) >>> 0;
  for (let i = 0; i < 4; i++) { msg.push(low & 0xff); low >>>= 8; }
  for (let i = 0; i < 4; i++) { msg.push(high & 0xff); high >>>= 8; }
  let a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  const rotl = (x, c) => ((x << c) | (x >>> (32 - c))) >>> 0;
  for (let off = 0; off < msg.length; off += 64) {
    const M = [];
    for (let j = 0; j < 16; j++) {
      M[j] = (msg[off + j * 4] | (msg[off + j * 4 + 1] << 8) | (msg[off + j * 4 + 2] << 16) | (msg[off + j * 4 + 3] << 24)) >>> 0;
    }
    let A = a0, B = b0, C = c0, D = d0;
    for (let i = 0; i < 64; i++) {
      let F, g;
      if (i < 16)      { F = (B & C) | (~B & D); g = i; }
      else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; }
      else if (i < 48) { F = B ^ C ^ D;          g = (3 * i + 5) % 16; }
      else             { F = C ^ (B | ~D);       g = (7 * i) % 16; }
      F = (F + A + K[i] + M[g]) >>> 0;
      A = D; D = C; C = B;
      B = (B + rotl(F, S[i])) >>> 0;
    }
    a0 = (a0 + A) >>> 0; b0 = (b0 + B) >>> 0; c0 = (c0 + C) >>> 0; d0 = (d0 + D) >>> 0;
  }
  const out = [];
  for (const w of [a0, b0, c0, d0]) out.push(w & 0xff, (w >>> 8) & 0xff, (w >>> 16) & 0xff, (w >>> 24) & 0xff);
  return out;
}
function __md5Hex(text) { return __bytesToHex(__md5Bytes(__utf8Bytes(String(text)))); }

// ---------------------------------------------------------------- AES-128 (FIPS-197), ECB + PKCS#7
function __gfMul(a, b) {
  let p = 0;
  for (let i = 0; i < 8; i++) {
    if (b & 1) p ^= a;
    const hi = a & 0x80;
    a = (a << 1) & 0xff;
    if (hi) a ^= 0x1b;
    b >>= 1;
  }
  return p;
}
const __sbox = (() => {
  const rotl8 = (x, n) => (((x << n) | (x >> (8 - n))) & 0xff);
  const s = new Uint8Array(256);
  for (let i = 0; i < 256; i++) {
    let inv = 0;
    if (i !== 0) {
      let r = 1, base = i, e = 254;
      while (e) { if (e & 1) r = __gfMul(r, base); base = __gfMul(base, base); e >>= 1; }
      inv = r;
    }
    s[i] = inv ^ rotl8(inv, 1) ^ rotl8(inv, 2) ^ rotl8(inv, 3) ^ rotl8(inv, 4) ^ 0x63;
  }
  return s;
})();
function __aesExpandKey(key) {
  const w = new Uint8Array(176);
  w.set(key);
  const rcon = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36];
  const temp = new Uint8Array(4);
  for (let i = 4; i < 44; i++) {
    for (let j = 0; j < 4; j++) temp[j] = w[(i - 1) * 4 + j];
    if (i % 4 === 0) {
      const t0 = __sbox[temp[1]] ^ rcon[i / 4 - 1];
      const t1 = __sbox[temp[2]];
      const t2 = __sbox[temp[3]];
      const t3 = __sbox[temp[0]];
      temp[0] = t0; temp[1] = t1; temp[2] = t2; temp[3] = t3;
    }
    for (let j = 0; j < 4; j++) w[i * 4 + j] = w[(i - 4) * 4 + j] ^ temp[j];
  }
  return w;
}
function __aesEncryptBlock(rk, block) {
  const s = new Uint8Array(block);
  const addRK = (round) => { for (let i = 0; i < 16; i++) s[i] ^= rk[round * 16 + i]; };
  const sub = () => { for (let i = 0; i < 16; i++) s[i] = __sbox[s[i]]; };
  const shift = () => {
    const t = new Uint8Array(s);
    for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) s[r + 4 * c] = t[r + 4 * ((c + r) % 4)];
  };
  const mix = () => {
    for (let c = 0; c < 4; c++) {
      const i = 4 * c, a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3];
      s[i]     = __gfMul(a0, 2) ^ __gfMul(a1, 3) ^ a2 ^ a3;
      s[i + 1] = a0 ^ __gfMul(a1, 2) ^ __gfMul(a2, 3) ^ a3;
      s[i + 2] = a0 ^ a1 ^ __gfMul(a2, 2) ^ __gfMul(a3, 3);
      s[i + 3] = __gfMul(a0, 3) ^ a1 ^ a2 ^ __gfMul(a3, 2);
    }
  };
  addRK(0);
  for (let round = 1; round < 10; round++) { sub(); shift(); mix(); addRK(round); }
  sub(); shift(); addRK(10);
  return s;
}
function __aesEcbEncryptHex(keyText, plainText) {
  const key = __utf8Bytes(String(keyText));
  if (key.length !== 16) throw new Error("aesEcbEncrypt: key must be 16 bytes, got " + key.length);
  const data = __utf8Bytes(String(plainText));
  const pad = 16 - (data.length % 16);
  for (let i = 0; i < pad; i++) data.push(pad);
  const rk = __aesExpandKey(new Uint8Array(key));
  const out = [];
  for (let off = 0; off < data.length; off += 16) {
    const enc = __aesEncryptBlock(rk, data.slice(off, off + 16));
    for (let i = 0; i < 16; i++) out.push(enc[i]);
  }
  return __bytesToHex(out);
}
// Exposed for the spike self-test (FIPS-197 block vector).
globalThis.__testAesBlock = (keyHex, blockHex) => {
  const parse = (h) => { const b = []; for (let i = 0; i < h.length; i += 2) b.push(parseInt(h.slice(i, i + 2), 16)); return b; };
  const rk = __aesExpandKey(new Uint8Array(parse(keyHex)));
  return __bytesToHex(__aesEncryptBlock(rk, parse(blockHex)));
};
globalThis.__testMd5 = __md5Hex;
globalThis.__testAesEcb = __aesEcbEncryptHex;

// ---------------------------------------------------------------- console
function __logLine(level, args) {
  try {
    const msg = args.map((a) => {
      if (typeof a === "string") return a;
      try { return JSON.stringify(a); } catch (e) { return String(a); }
    }).join(" ");
    sendMessage("log", JSON.stringify({ level, msg }));
  } catch (e) { /* nowhere to log to */ }
}
globalThis.console = {
  log: (...a) => __logLine("log", a),
  info: (...a) => __logLine("info", a),
  warn: (...a) => __logLine("warn", a),
  error: (...a) => __logLine("error", a),
};

// ---------------------------------------------------------------- timers (via Dart bridge)
let __timerSeq = 1;
const __timers = new Map();
globalThis.setTimeout = (cb, ms, ...args) => {
  const id = __timerSeq++;
  __timers.set(id, true);
  sendMessage("timer", String(ms || 0)).then(() => {
    if (__timers.delete(id) && typeof cb === "function") {
      try { cb(...args); } catch (e) { __logLine("error", ["setTimeout callback: " + (e && e.stack || e)]); }
    }
  });
  return id;
};
globalThis.clearTimeout = (id) => { __timers.delete(id); };
globalThis.setInterval = (cb, ms, ...args) => {
  const id = __timerSeq++;
  __timers.set(id, true);
  const tick = () => {
    if (!__timers.has(id)) return;
    try { cb(...args); } catch (e) { __logLine("error", ["setInterval callback: " + (e && e.stack || e)]); }
    if (__timers.has(id)) sendMessage("timer", String(ms || 0)).then(tick);
  };
  sendMessage("timer", String(ms || 0)).then(tick);
  return id;
};
globalThis.clearInterval = (id) => { __timers.delete(id); };

// ---------------------------------------------------------------- AbortController
globalThis.AbortController = class AbortController {
  constructor() {
    this.signal = {
      aborted: false,
      _listeners: [],
      addEventListener: function (type, fn) { if (type === "abort") this._listeners.push(fn); },
      removeEventListener: function (type, fn) { this._listeners = this._listeners.filter((f) => f !== fn); },
    };
  }
  abort() {
    if (this.signal.aborted) return;
    this.signal.aborted = true;
    for (const fn of this.signal._listeners) { try { fn(); } catch (e) {} }
  }
};

// ---------------------------------------------------------------- URL (minimal: protocol/host/pathname/search/href)
globalThis.URL = class URL {
  constructor(url, base) {
    let text = String(url);
    if (base && !/^[a-z][a-z0-9+.-]*:/i.test(text)) {
      const b = new URL(base);
      text = text.startsWith("/") ? b.origin + text : b.origin + b.pathname.replace(/[^/]*$/, "") + text;
    }
    const m = /^([a-z][a-z0-9+.-]*:)\/\/([^/?#]*)([^?#]*)(\?[^#]*)?(#.*)?$/i.exec(text);
    if (!m) throw new TypeError("Invalid URL: " + text);
    this.protocol = m[1].toLowerCase();
    this.host = m[2];
    const hp = m[2].split(":");
    this.hostname = hp[0];
    this.port = hp.length > 1 ? hp[1] : "";
    this.pathname = m[3] || "/";
    this.search = m[4] || "";
    this.hash = m[5] || "";
    this.origin = this.protocol + "//" + this.host;
    this.href = this.origin + this.pathname + this.search + this.hash;
  }
  toString() { return this.href; }
};

// ---------------------------------------------------------------- fetch (via Dart bridge)
globalThis.fetch = async (url, opts) => {
  opts = opts || {};
  const raw = await sendMessage("fetch", JSON.stringify({
    url: String(url),
    method: opts.method || "GET",
    headers: opts.headers || {},
    body: opts.body != null ? String(opts.body) : null,
  }));
  const r = JSON.parse(raw);
  if (r.error) throw new TypeError("fetch failed: " + r.error);
  const map = r.headers || {};
  const headers = {
    get: (name) => {
      const v = map[String(name).toLowerCase()];
      return v && v.length ? v.join(", ") : null;
    },
    getSetCookie: () => map["set-cookie"] || [],
    has: (name) => !!map[String(name).toLowerCase()],
  };
  return {
    ok: r.status >= 200 && r.status < 300,
    status: r.status,
    statusText: "",
    headers,
    url: String(url),
    json: async () => JSON.parse(r.body),
    text: async () => r.body,
  };
};

// ---------------------------------------------------------------- host
const __cfg = globalThis.__hostConfig || { storage: {}, settings: {}, platform: "android", arch: "arm64", dir: "", dataDir: "" };
// flutter_js resolves sendMessage with a real Promise only for async Dart
// handlers; for sync handlers it may return undefined. Never chain blindly.
function __fireAndForget(channel, payload) {
  try {
    const p = sendMessage(channel, payload);
    if (p && typeof p.then === "function") p.then(() => {}, () => {});
  } catch (e) { /* bridge unavailable: persistence is best-effort in the spike */ }
}

const __storageMem = {};
for (const k of Object.keys(__cfg.storage || {})) __storageMem[k] = __cfg.storage[k];
globalThis.host = {
  platform: __cfg.platform,
  arch: __cfg.arch,
  dir: __cfg.dir,
  dataDir: __cfg.dataDir,
  storage: {
    get: (key) => (__storageMem[key] === undefined ? null : __storageMem[key]),
    set: (key, value) => {
      __storageMem[key] = value;
      __fireAndForget("storageSet", JSON.stringify({ key, value }));
    },
    remove: (key) => {
      delete __storageMem[key];
      __fireAndForget("storageRemove", JSON.stringify({ key }));
    },
  },
  setting: (key) => (__cfg.settings && __cfg.settings[key] !== undefined ? __cfg.settings[key] : null),
  t: (text) => text,
  language: () => "zh-CN",
  crypto: {
    md5: (text) => __md5Hex(text),
    aesEcbEncrypt: (key, text) => __aesEcbEncryptHex(key, text),
  },
  openURL: (url) => { __logLine("log", ["host.openURL: " + url]); },
  removeDataDir: (name) => { __logLine("log", ["host.removeDataDir: " + name]); },
  // Sign-in UX: signInPrompt is fire-and-forget (the app shows the QR /
  // status the plugin keeps updating; nothing is answered back), and
  // webSignIn round-trips through the Dart side, which shows the page
  // and answers {cookie} — or an error the plugin sees as a rejection.
  signInPrompt: (prompt) => { __fireAndForget("signInPrompt", JSON.stringify(prompt || {})); },
  webSignIn: async (opts) => {
    const raw = await sendMessage("webSignIn", JSON.stringify(opts || {}));
    const r = JSON.parse(raw);
    if (r.error) throw new Error(r.error);
    return { cookie: r.cookie || "" };
  },
  waitForRedirect: async () => { throw new Error("host.waitForRedirect is not implemented in this host"); },
  spawn: () => { throw new Error("host.spawn is not implemented in this host"); },
};
