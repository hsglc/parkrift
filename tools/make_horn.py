"""Synthesizes ParkPark's car horn (mono, 22050 Hz, 16-bit) to match the other effects."""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 22050
d = 0.42
t = np.arange(int(d * SR)) / SR
# Soft dual-tone horn (about F#4 + A#4) with gentle harmonics and smooth fades
sig = np.zeros_like(t)
for f in (370.0, 466.0):
    phase = 2 * np.pi * f * t
    sig += np.sin(phase) + 0.30 * np.sin(2 * phase) + 0.12 * np.sin(3 * phase)
sig = np.tanh(sig * 0.8)
b, a = butter(2, 1700 / (SR / 2), btype="low")
sig = lfilter(b, a, sig)
b, a = butter(1, 180 / (SR / 2), btype="high")
sig = lfilter(b, a, sig)
env = np.ones_like(t)
att, rel = int(0.03 * SR), int(0.14 * SR)
env[:att] = np.linspace(0, 1, att)
env[-rel:] = np.linspace(1, 0, rel)
sig *= env
sig = sig / np.max(np.abs(sig)) * 0.7
wavfile.write(sys.argv[1], SR, (sig * 32767).astype(np.int16))
print("ok")
