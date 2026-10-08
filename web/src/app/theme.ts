/** Color for a temperature: slate when cold, then rust → ember → amber → white-hot. */
export function heatColor(fahrenheit: number): string {
  const stops: [number, [number, number, number]][] = [
    [100, [74, 84, 105]],
    [300, [122, 46, 18]],
    [450, [232, 118, 43]],
    [580, [255, 197, 107]],
    [700, [255, 243, 214]],
  ];
  const f = Math.min(Math.max(fahrenheit, stops[0]![0]), stops[stops.length - 1]![0]);
  for (let i = 1; i < stops.length; i++) {
    const [f1, c1] = stops[i]!;
    if (f <= f1) {
      const [f0, c0] = stops[i - 1]!;
      const t = (f - f0) / (f1 - f0);
      const mix = (a: number, b: number) => Math.round(a + (b - a) * t);
      return `rgb(${mix(c0[0], c1[0])} ${mix(c0[1], c1[1])} ${mix(c0[2], c1[2])})`;
    }
  }
  const last = stops[stops.length - 1]![1];
  return `rgb(${last[0]} ${last[1]} ${last[2]})`;
}

export const DIM = "#9aa3b2";
