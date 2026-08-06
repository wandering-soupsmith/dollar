// Guilloché: the fine interlaced line-work engraved on banknotes. Rendered as an
// inline SVG so it inherits `currentColor` and stays crisp at any size. Two motifs — a corner rosette
// (concentric, rotated ellipses) and a field of woven sine lines — combine into the note texture.

type Props = {
  /** rosette placement */
  rosette?: "left" | "right" | "none";
  className?: string;
};

function Rosette({ cx, cy }: { cx: number; cy: number }) {
  const rings = Array.from({ length: 11 }, (_, i) => i);
  return (
    <g transform={`translate(${cx} ${cy})`}>
      {rings.map((i) => {
        const rx = 26 + i * 7;
        const ry = 14 + i * 7;
        const rot = i * 16;
        return (
          <ellipse
            key={i}
            rx={rx}
            ry={ry}
            transform={`rotate(${rot})`}
            fill="none"
            stroke="currentColor"
            strokeWidth={0.5}
          />
        );
      })}
    </g>
  );
}

function Waves() {
  // Woven horizontal sine lines across the full width.
  const lines = Array.from({ length: 22 }, (_, i) => i);
  const width = 640;
  const step = 12;
  return (
    <g>
      {lines.map((i) => {
        const y = i * step + 6;
        const amp = 5 + (i % 3) * 2;
        const phase = (i % 4) * 6;
        let d = `M0 ${y}`;
        for (let x = 0; x <= width; x += 16) {
          const yy = y + Math.sin((x + phase * 10) / 26) * amp;
          d += ` L${x} ${yy.toFixed(1)}`;
        }
        return <path key={i} d={d} fill="none" stroke="currentColor" strokeWidth={0.4} />;
      })}
    </g>
  );
}

export function Guilloche({ rosette = "right", className }: Props) {
  return (
    <svg
      className={className}
      viewBox="0 0 640 280"
      preserveAspectRatio="xMidYMid slice"
      aria-hidden="true"
      focusable="false"
    >
      <Waves />
      {rosette === "right" && <Rosette cx={545} cy={150} />}
      {rosette === "left" && <Rosette cx={95} cy={150} />}
    </svg>
  );
}
