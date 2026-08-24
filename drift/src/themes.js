/* DRIFT — per-zone visual identity.
 *
 * Every zone used to render identically and differ only by a drone pitch, which
 * meant progress never *felt* like progress. Each zone now owns a palette, a
 * sky, a hull treatment and a hazard colour, so you can tell where you are from
 * a glance at a screenshot.
 *
 * These are presentation only. Nothing here changes collision, reach, or
 * anything the verifier depends on — a theme can never make a sector unsolvable.
 */
export const THEMES = [
  { // I · HULL — cold, intact, powered down. The baseline everything reads against.
    sky:      "#070912",
    glow:     "rgba(30,42,74,.30)",
    hull:     "#1A2033", hullIn: "#11162a", hullEdge: "#2F3A57",
    grid:     "rgba(47,58,87,.14)",
    star:     "#9FB0D8", starCount: 80, starAlpha: 1,
    hazard:   "#FF7A5C",
    rivet:    "rgba(167,139,250,.10)",
    vignette: .45,
    drone:    46,
  },
  { // II · CARGO — warmer, dirtier, industrial. Amber worklights still running.
    sky:      "#0A0A10",
    glow:     "rgba(74,58,30,.26)",
    hull:     "#22201C", hullIn: "#14120F", hullEdge: "#4A4232",
    grid:     "rgba(74,66,50,.16)",
    star:     "#C8B590", starCount: 46, starAlpha: .8,
    hazard:   "#FF7A5C",
    rivet:    "rgba(255,196,107,.13)",
    vignette: .52,
    drone:    53,
  },
  { // III · CORE — irradiated violet. The lattice bleeding into the walls.
    sky:      "#0A0714",
    glow:     "rgba(70,40,110,.30)",
    hull:     "#1F1830", hullIn: "#140F22", hullEdge: "#493A6B",
    grid:     "rgba(73,58,107,.17)",
    star:     "#C2A8F0", starCount: 62, starAlpha: .85,
    hazard:   "#FF6BA0",
    rivet:    "rgba(167,139,250,.20)",
    vignette: .58,
    drone:    60,
  },
  { // IV · VOID — almost no hull left. Deep, cold, and very empty.
    sky:      "#04060E",
    glow:     "rgba(20,60,74,.24)",
    hull:     "#141D26", hullIn: "#0B1119", hullEdge: "#27414E",
    grid:     "rgba(39,65,78,.13)",
    star:     "#CFE6F5", starCount: 130, starAlpha: 1.15,
    hazard:   "#FF8A6B",
    rivet:    "rgba(94,224,200,.12)",
    vignette: .62,
    drone:    41,
  },
  { // V · RELAY — the outbound station. Live power, green signal, machinery moving.
    sky:      "#05100C",
    glow:     "rgba(24,80,58,.26)",
    hull:     "#152620", hullIn: "#0C1712", hullEdge: "#2C5544",
    grid:     "rgba(44,85,68,.16)",
    star:     "#A7E8C8", starCount: 70, starAlpha: .9,
    hazard:   "#FF7A5C",
    rivet:    "rgba(94,224,200,.16)",
    vignette: .5,
    drone:    67,
  },
];

export const themeFor = (zoneIndex) => THEMES[Math.min(zoneIndex, THEMES.length - 1)];
