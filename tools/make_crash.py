"""Synthesizes the car crash sound (Hop/Audio/crash.wav, 22.05 kHz mono 16-bit):
a body thump, a crunch of bent metal (inharmonic ringing partials plus band-passed noise
bursts), falling glass and plastic bits, and a short scrape."""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 22050
rng = np.random.default_rng(7)
length = 1.25
t = np.arange(int(SR * length)) / SR


def band(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], btype='band')
    return lfilter(b, a, x)


def low(x, cut, order=2):
    b, a = butter(order, cut / (SR / 2), btype='low')
    return lfilter(b, a, x)


out = np.zeros_like(t)
# Thump: a falling low sine with a soft click on top
f = 95 * np.exp(-t * 6) + 42
phase = 2 * np.pi * np.cumsum(f) / SR
out += 0.9 * np.sin(phase) * np.exp(-t * 9)
out += 0.5 * low(rng.normal(size=len(t)), 900) * np.exp(-t * 40)

# Metal crunch: inharmonic panel partials, slightly detuned, ringing out
for freq, amp, decay in [(310, 0.35, 7), (447, 0.3, 8), (683, 0.28, 9), (1021, 0.22, 11), (1530, 0.18, 13),
                         (2210, 0.12, 15), (3170, 0.08, 18)]:
    wobble = 1 + 0.01 * np.sin(2 * np.pi * (5 + rng.random() * 4) * t)
    out += amp * np.sin(2 * np.pi * freq * wobble * t + rng.random() * 6) * np.exp(-t * decay)
# Crunch bursts: several short noise grains in the first 0.3 s (the panels folding)
for _ in range(14):
    start = rng.uniform(0, 0.3)
    dur = rng.uniform(0.015, 0.06)
    grain = (t >= start) & (t < start + dur)
    env = np.zeros_like(t)
    env[grain] = np.hanning(grain.sum())
    lo = rng.uniform(500, 1500)
    out += rng.uniform(0.25, 0.6) * band(rng.normal(size=len(t)), lo, lo * 3) * env

# Glass and plastic bits: short high pings, scattered over the first second
for _ in range(26):
    start = rng.uniform(0.05, 0.95)
    freq = rng.uniform(2800, 7500)
    amp = rng.uniform(0.04, 0.14) * np.exp(-start * 2)
    seg = t >= start
    out[seg] += amp * np.sin(2 * np.pi * freq * (t[seg] - start)) * np.exp(-(t[seg] - start) * rng.uniform(40, 90))

# Scrape: band-passed noise fading out
scrape = band(rng.normal(size=len(t)), 900, 4200) * 0.12 * np.clip((t - 0.08) * 8, 0, 1) * np.exp(-t * 4)
out += scrape

out *= np.clip(t / 0.002, 0, 1)            # no click at the start
out *= np.clip((length - t) / 0.08, 0, 1)  # fade at the end
out = np.tanh(out * 1.4)                     # a little saturation, like a car stereo crash
out /= np.max(np.abs(out)) / 0.92
wavfile.write(sys.argv[1], SR, (out * 32767).astype(np.int16))
print('crash', len(out) / SR, 's')
