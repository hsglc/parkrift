"""Synthesizes ParkPark's original music loop and sound effects."""
import sys, os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
SR = 44100
rng = np.random.default_rng(42)

def note_freq(n):  # MIDI note -> Hz
    return 440.0 * 2 ** ((n - 69) / 12)

def env_adsr(length, a=0.01, d=0.1, s=0.6, r=0.1):
    n = int(length * SR)
    e = np.zeros(n)
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    ns = max(n - na - nd - nr, 0)
    parts = [np.linspace(0, 1, max(na, 1), endpoint=False),
             np.linspace(1, s, max(nd, 1), endpoint=False),
             np.full(ns, s),
             np.linspace(s, 0, max(nr, 1))]
    e = np.concatenate(parts)[:n]
    if len(e) < n:
        e = np.pad(e, (0, n - len(e)))
    return e

def saw(f, t):
    return 2 * ((f * t) % 1.0) - 1

def square(f, t, duty=0.5):
    return np.where((f * t) % 1.0 < duty, 1.0, -1.0)

def tri(f, t):
    return 2 * np.abs(2 * ((f * t) % 1.0) - 1) - 1

def lowpass(x, cutoff, order=2):
    b, a = butter(order, cutoff / (SR / 2), btype="low")
    return lfilter(b, a, x)

def highpass(x, cutoff, order=2):
    b, a = butter(order, cutoff / (SR / 2), btype="high")
    return lfilter(b, a, x)

def place(buf, sig, start, pan=0.0, gain=1.0):
    i = int(start * SR)
    end = min(i + len(sig), buf.shape[0])
    if i >= buf.shape[0]:
        return
    s = sig[: end - i] * gain
    left = np.cos((pan + 1) * np.pi / 4)
    right = np.sin((pan + 1) * np.pi / 4)
    buf[i:end, 0] += s * left
    buf[i:end, 1] += s * right

# ---------------------------------------------------------------- music
BPM = 104
beat = 60 / BPM
bar = beat * 4
BARS = 16
length = bar * BARS
tail = 3.0
mix = np.zeros((int((length + tail) * SR), 2))

# Am, F, C, G  (MIDI roots and chord tones)
chords = [
    (57, [57, 60, 64, 69]),   # Am
    (53, [53, 57, 60, 65]),   # F
    (48, [52, 55, 60, 64]),   # C
    (55, [55, 59, 62, 67]),   # G
]

for b in range(BARS):
    root, tones = chords[b % 4]
    t0 = b * bar

    # Pad: detuned saws, filtered, gentle swell
    dur = bar + 0.25
    t = np.arange(int(dur * SR)) / SR
    pad = np.zeros_like(t)
    for n in tones[:3]:
        f = note_freq(n)
        pad += saw(f * 0.997, t) + saw(f * 1.003, t)
    pad = lowpass(pad, 1400) * env_adsr(dur, a=0.25, d=0.3, s=0.8, r=0.35)
    place(mix, pad, t0, pan=-0.3, gain=0.045)
    place(mix, pad, t0 + 0.012, pan=0.3, gain=0.045)

    # Arpeggio: 16th-note plucks
    sixteenth = beat / 4
    pattern = [0, 1, 2, 3, 2, 1, 2, 3, 0, 2, 3, 2, 1, 2, 3, 1]
    for i, idx in enumerate(pattern):
        n = tones[idx] + 12
        d = sixteenth * 0.95
        t = np.arange(int(d * SR)) / SR
        f = note_freq(n)
        pluck = (square(f, t, 0.3) * 0.6 + tri(f, t) * 0.4) * np.exp(-t * 22)
        pluck = lowpass(pluck, 3200)
        accent = 1.0 if i % 4 == 0 else 0.7
        place(mix, pluck, t0 + i * sixteenth, pan=0.35 if i % 2 else -0.15, gain=0.11 * accent)

    # Bass: eighth notes, root and octave
    eighth = beat / 2
    bass_line = [0, 0, 12, 0, 0, 7, 12, 0]
    for i, step in enumerate(bass_line):
        n = root - 12 + step
        d = eighth * 0.9
        t = np.arange(int(d * SR)) / SR
        f = note_freq(n)
        tone = (tri(f, t) * 0.7 + np.sin(2 * np.pi * f * t) * 0.6) * env_adsr(d, a=0.005, d=0.12, s=0.5, r=0.05)
        place(mix, lowpass(tone, 900), t0 + i * eighth, gain=0.30)

    # Drums
    for beat_i in range(4):
        bt = t0 + beat_i * beat
        # Kick on 1 and 3 (plus a pickup on the last 8th of every 4th bar)
        if beat_i in (0, 2):
            d = 0.35
            t = np.arange(int(d * SR)) / SR
            freq = 120 * np.exp(-t * 18) + 45
            phase = 2 * np.pi * np.cumsum(freq) / SR
            kick = np.sin(phase) * np.exp(-t * 9)
            place(mix, kick, bt, gain=0.55)
        # Snare on 2 and 4
        if beat_i in (1, 3):
            d = 0.25
            t = np.arange(int(d * SR)) / SR
            noise = highpass(rng.standard_normal(len(t)), 1500) * np.exp(-t * 20)
            body = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30)
            place(mix, noise * 0.5 + body * 0.5, bt, gain=0.30)
        # Hats on every 8th
        for h in range(2):
            d = 0.06 if h == 0 else 0.12
            t = np.arange(int(d * SR)) / SR
            hat = highpass(rng.standard_normal(len(t)), 7000) * np.exp(-t * (70 if h == 0 else 30))
            place(mix, hat, bt + h * beat / 2, pan=0.4, gain=0.07 if h == 0 else 0.09)
    if b % 4 == 3:
        d = 0.3
        t = np.arange(int(d * SR)) / SR
        freq = 110 * np.exp(-t * 18) + 45
        kick = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 10)
        place(mix, kick, t0 + 3.5 * beat, gain=0.45)

# Lead melody in the second half (C major pentatonic hook)
melody = [  # (bar offset in beats, midi, length in beats)
    (0, 76, 0.5), (0.5, 79, 0.5), (1, 81, 1), (2.5, 79, 0.5), (3, 76, 1),
    (4, 74, 0.5), (4.5, 76, 0.5), (5, 77, 1), (6, 76, 0.5), (6.5, 74, 0.5), (7, 72, 1),
    (8, 72, 0.5), (8.5, 74, 0.5), (9, 76, 1), (10, 79, 0.5), (10.5, 76, 0.5), (11, 74, 1),
    (12, 74, 0.5), (12.5, 71, 0.5), (13, 74, 1), (14, 79, 2),
]
for repeat in (8, 12):
    for start, n, ln in melody:
        d = ln * beat
        t = np.arange(int((d + 0.15) * SR)) / SR
        f = note_freq(n)
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t)
        lead = (square(f * vib, t, 0.25) * 0.5 + np.sin(2 * np.pi * f * vib * t) * 0.7)
        lead = lowpass(lead, 4200) * env_adsr(d + 0.15, a=0.01, d=0.08, s=0.7, r=0.15)
        place(mix, lead, repeat * bar + start * beat, pan=0.1, gain=0.085)
        # Simple echo
        place(mix, lead, repeat * bar + start * beat + beat * 0.75, pan=-0.4, gain=0.03)

# Seamless loop: fold the tail back onto the start
loop_n = int(length * SR)
music = mix[:loop_n].copy()
music[: len(mix) - loop_n] += mix[loop_n:]
music = np.tanh(music * 1.4) / np.tanh(1.4)
music /= np.max(np.abs(music)) / 0.89
wavfile.write(os.path.join(OUT, "music.wav"), SR, (music * 32767).astype(np.int16))

# ---------------------------------------------------------------- engine loop (1 s, seamless)
d = 1.0
t = np.arange(int(d * SR)) / SR
base = 50.0  # Hz, integer cycles per loop
engine = np.zeros_like(t)
for k, a in [(1, 1.0), (2, 0.55), (3, 0.35), (4, 0.2), (6, 0.12)]:
    engine += a * np.sin(2 * np.pi * base * k * t + k)
firing = 0.65 + 0.35 * np.sin(2 * np.pi * 25 * t) ** 2
noise = lowpass(rng.standard_normal(len(t)), 600)
noise = noise * np.hanning(len(t))  # fade so the loop edge is clean
engine = engine * firing + noise * 0.25
engine = lowpass(engine, 1200)
fade = int(0.01 * SR)
engine[:fade] *= np.linspace(0.6, 1, fade)
engine[-fade:] *= np.linspace(1, 0.6, fade)
engine /= np.max(np.abs(engine)) / 0.8
wavfile.write(os.path.join(OUT, "engine.wav"), SR, (engine * 32767).astype(np.int16))

# ---------------------------------------------------------------- sound effects
def save(name, sig):
    sig = sig / max(np.max(np.abs(sig)), 1e-6) * 0.9
    wavfile.write(os.path.join(OUT, name), SR, (sig * 32767).astype(np.int16))

# Bump: low thud + crunch
d = 0.35
t = np.arange(int(d * SR)) / SR
thud = np.sin(2 * np.pi * (90 * np.exp(-t * 12) + 40) * t) * np.exp(-t * 14)
crunch = lowpass(rng.standard_normal(len(t)), 2500) * np.exp(-t * 25)
save("bump.wav", thud * 0.8 + crunch * 0.5)

# Countdown beep and go
def beep(f, d, decay):
    t = np.arange(int(d * SR)) / SR
    return (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t)) * np.exp(-t * decay) * env_adsr(d, a=0.005, d=0.02, s=1, r=0.03)
save("beep.wav", beep(880, 0.16, 12))
save("go.wav", beep(1320, 0.4, 5))

# Park chime: rising arpeggio
chime = np.zeros(int(0.9 * SR))
for i, n in enumerate([72, 76, 79, 84]):
    t = np.arange(int(0.5 * SR)) / SR
    f = note_freq(n)
    tone = (np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * 2 * f * t)) * np.exp(-t * 6)
    s = int(i * 0.09 * SR)
    chime[s:s + len(tone)] += tone[: len(chime) - s]
save("park.wav", chime)

# UI click
t = np.arange(int(0.05 * SR)) / SR
save("click.wav", np.sin(2 * np.pi * 1800 * t) * np.exp(-t * 90))
print("ok")
