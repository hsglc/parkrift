"""Synthesizes the arcade sounds (all original), 22.05 kHz mono 16-bit:
  skid.wav   tyre screech loop (seamless): a wavering squeal over rubbery noise
  siren.wav  police siren loop (two-tone wail)
  rain.wav   rain loop (seamless): soft hiss with drops
  whoosh.wav near-miss pass-by: a doppler swoosh
Usage: python3 make_arcade_sounds.py <Hop/Audio>
"""
import sys, os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 22050
OUT = sys.argv[1]
rng = np.random.default_rng(11)


def band(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], btype='band')
    return lfilter(b, a, x)


def low(x, cut, order=2):
    b, a = butter(order, cut / (SR / 2), btype='low')
    return lfilter(b, a, x)


def loop_fade(x, fade=0.25):
    """Crossfades the end into the start so the loop has no seam."""
    n = int(SR * fade)
    head, tail = x[:n].copy(), x[-n:].copy()
    ramp = np.linspace(0, 1, n)
    x = x[:-n].copy()
    x[:n] = head * ramp + tail * (1 - ramp)
    return x


def save(name, x, peak=0.9):
    x = x / np.max(np.abs(x)) * peak
    wavfile.write(os.path.join(OUT, name), SR, (x * 32767).astype(np.int16))
    print(name, round(len(x) / SR, 2), 's')


# Tyre screech: 2.25 s loop
t = np.arange(int(SR * 2.25)) / SR
wobble = 1 + 0.035 * np.sin(2 * np.pi * 5.3 * t) + 0.02 * np.sin(2 * np.pi * 11.7 * t + 1)
f0 = 1150 * wobble
phase = 2 * np.pi * np.cumsum(f0) / SR
squeal = np.sin(phase) + 0.45 * np.sin(2 * phase + 0.4) + 0.2 * np.sin(3 * phase + 1.1)
amp = 0.75 + 0.25 * low(rng.normal(size=len(t)), 6) * 8
rubber = band(rng.normal(size=len(t)), 600, 3800) * 0.9
skid = squeal * np.clip(amp, 0.3, 1.2) * 0.55 + rubber * 0.5
save('skid.wav', loop_fade(np.tanh(skid * 1.2)), 0.8)

# Siren: 2 s loop, rising and falling wail (classic two-step tone on top)
t = np.arange(int(SR * 2.0)) / SR
sweep = 0.5 - 0.5 * np.cos(2 * np.pi * t / 2.0)
f = 650 + 650 * sweep
phase = 2 * np.pi * np.cumsum(f) / SR
siren = np.sign(np.sin(phase)) * 0.35 + np.sin(phase) * 0.65
siren = low(siren, 3500)
save('siren.wav', siren, 0.7)

# Rain: 3 s loop
t = np.arange(int(SR * 3.3)) / SR
hiss = band(rng.normal(size=len(t)), 900, 7000) * 0.5 + low(rng.normal(size=len(t)), 400) * 0.25
drops = np.zeros_like(t)
for _ in range(220):
    start = rng.integers(0, len(t) - 400)
    n = rng.integers(60, 300)
    f = rng.uniform(1800, 5200)
    seg = np.arange(n) / SR
    drops[start:start + n] += rng.uniform(0.05, 0.25) * np.sin(2 * np.pi * f * seg) * np.exp(-seg * 90)
save('rain.wav', loop_fade(hiss + drops), 0.6)

# Whoosh: 0.7 s pass-by with a pitch drop
t = np.arange(int(SR * 0.7)) / SR
env = np.exp(-((t - 0.25) / 0.12) ** 2)
noise = rng.normal(size=len(t))
lo_f = 900 - 500 * np.clip((t - 0.25) / 0.3, -1, 1)
whoosh = np.zeros_like(t)
for k in range(0, len(t), 512):
    seg = slice(k, min(len(t), k + 512))
    c = float(lo_f[k])
    whoosh[seg] = band(noise, max(120, c * 0.6), c * 2.2)[seg]
save('whoosh.wav', whoosh * env, 0.8)
