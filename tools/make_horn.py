"""Synthesizes ParkPark's car horn (mono, 22050 Hz, 16-bit) to match the other effects."""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 22050
d = 0.55
t = np.arange(int(d * SR)) / SR
# Classic dual-tone horn (about F#4 + A#4), rich harmonics from a clipped mix
sig = np.zeros_like(t)
for f in (370.0, 466.0):
    phase = 2 * np.pi * f * t + 0.6 * np.sin(2 * np.pi * f * t)
    sig += np.sin(phase) + 0.5 * np.sign(np.sin(phase)) * 0.6
sig = np.tanh(sig * 1.8)
b, a = butter(2, 3200 / (SR / 2), btype="low")
sig = lfilter(b, a, sig)
b, a = butter(1, 180 / (SR / 2), btype="high")
sig = lfilter(b, a, sig)
env = np.ones_like(t)
att, rel = int(0.012 * SR), int(0.07 * SR)
env[:att] = np.linspace(0, 1, att)
env[-rel:] = np.linspace(1, 0, rel)
sig *= env
sig = sig / np.max(np.abs(sig)) * 0.9
wavfile.write(sys.argv[1], SR, (sig * 32767).astype(np.int16))
print("ok")
