"""Synthesizes the nitro whoosh (mono, 22050 Hz, 16-bit) to match the other effects."""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 22050
d = 1.3
t = np.arange(int(d * SR)) / SR
rng = np.random.default_rng(7)
noise = rng.standard_normal(len(t))
# Rising band of noise (jet whoosh) in short blocks with a sweeping band-pass
out = np.zeros_like(t)
block = 512
for start in range(0, len(t), block):
    seg = noise[start:start + block]
    progress = start / len(t)
    center = 500 + 2200 * min(1, progress * 2.2)
    low, high = center * 0.6, min(center * 1.6, SR / 2 - 100)
    b, a = butter(2, [low / (SR / 2), high / (SR / 2)], btype="band")
    out[start:start + block] = lfilter(b, a, seg)
# Low rumble with a pitch rise
freq = 55 + 50 * np.minimum(1, t * 2)
rumble = np.sin(2 * np.pi * np.cumsum(freq) / SR) + 0.4 * np.sin(4 * np.pi * np.cumsum(freq) / SR)
sig = out * 1.0 + rumble * 0.35
env = np.minimum(1, t / 0.05) * np.exp(-np.maximum(0, t - 0.5) * 2.6)
sig *= env
sig = sig / np.max(np.abs(sig)) * 0.85
wavfile.write(sys.argv[1], SR, (sig * 32767).astype(np.int16))
print("ok")
