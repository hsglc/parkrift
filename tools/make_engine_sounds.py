"""Synthesizes the car's engine and driving sounds (original, procedural):

  engine_low.wav   seamless 1 s loop of a four-cylinder at about 1560 rpm (firing 52 Hz)
  engine_high.wav  seamless 1 s loop of the same engine near 3960 rpm (firing 132 Hz), brighter
  wind.wav         seamless 2 s loop of wind noise at speed
  shift.wav        gear change: a short mechanical clunk with a puff of air
  pop.wav          exhaust pop on lifting off at high revs

The game crossfades the two engine loops by rpm and pitches each with a varispeed unit, so the
pitch follows the gearbox (rises through a gear, drops on each upshift).

Usage: python3 make_engine_sounds.py <Hop/Audio>
"""
import sys, os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter, sosfiltfilt

OUT = sys.argv[1]
SR = 22050
rng = np.random.default_rng(7)


def band(x, low, high, order=2):
    sos = butter(order, [low / (SR / 2), high / (SR / 2)], btype='band', output='sos')
    return sosfiltfilt(sos, x)


def lowpass(x, cutoff, order=2):
    sos = butter(order, cutoff / (SR / 2), btype='low', output='sos')
    return sosfiltfilt(sos, x)


def circular_noise(n, low, high):
    """Band-limited noise that loops without a seam (filtered in the frequency domain)."""
    spectrum = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / SR)
    spectrum[(freqs < low) | (freqs > high)] = 0
    return np.fft.irfft(spectrum, n)


def engine(firing, seconds, brightness, rumble):
    """`firing`: combustion pulses per second (whole number of cycles per loop)."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    phase = (firing * t) % 1.0
    # Each combustion: a sharp pressure pulse that decays within the cycle
    pulse = np.exp(-phase * (6 + 10 * brightness)) - np.exp(-6 - 10 * brightness)
    # Slight cylinder-to-cylinder unevenness (repeats every 4 pulses, so the loop stays seamless)
    cylinder = np.floor(firing * t).astype(int) % 4
    pulse *= np.array([1.0, 0.86, 0.95, 0.8])[cylinder]
    tone = pulse - pulse.mean()
    # Harmonic body of the exhaust note
    for k, a in [(0.5, 0.35 * rumble), (1, 0.5), (2, 0.28 * brightness), (3, 0.16 * brightness)]:
        tone += a * np.sin(2 * np.pi * firing * k * t + k * 1.3)
    # Exhaust hiss and intake roar, pulsing with the firing
    hiss = circular_noise(n, 300, 900 + 2500 * brightness) * (0.6 + 0.4 * np.cos(2 * np.pi * phase))
    sig = tone + hiss * (0.25 + 0.35 * brightness)
    sig = np.tanh(sig * 1.6)
    # Low pass in the frequency domain too, so the loop has no seam
    spectrum = np.fft.rfft(sig)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    cutoff = 1300 + 2600 * brightness
    spectrum *= 1 / np.sqrt(1 + (freqs / cutoff) ** 4)
    sig = np.fft.irfft(spectrum, n)
    return sig / np.max(np.abs(sig)) * 0.85


def save(name, sig):
    wavfile.write(os.path.join(OUT, name), SR, (np.clip(sig, -1, 1) * 32767).astype(np.int16))


save('engine_low.wav', engine(52, 1.0, 0.25, 1.0))
save('engine_high.wav', engine(132, 1.0, 1.0, 0.5))

# Wind: broad noise with a slow swell (whole cycles per loop)
n = 2 * SR
t = np.arange(n) / SR
wind = circular_noise(n, 120, 1800) * (0.75 + 0.25 * np.sin(2 * np.pi * 0.5 * t))
save('wind.wav', wind / np.max(np.abs(wind)) * 0.7)

# Gear change: metallic clunk then a short puff of air
n = int(0.35 * SR)
t = np.arange(n) / SR
clunk = (np.sin(2 * np.pi * 180 * t) + 0.5 * np.sin(2 * np.pi * 410 * t)) * np.exp(-t * 60)
puff = band(rng.standard_normal(n), 1500, 6000) * np.exp(-((t - 0.09) / 0.06) ** 2) * 0.6
shift = clunk * 0.8 + puff
save('shift.wav', shift / np.max(np.abs(shift)) * 0.8)

# Exhaust pop: two or three quick cracks with a low thump
n = int(0.3 * SR)
t = np.arange(n) / SR
pop = np.zeros(n)
for start, gain in [(0.0, 1.0), (0.06, 0.6), (0.13, 0.4)]:
    i = int(start * SR)
    m = n - i
    tt = np.arange(m) / SR
    crack = band(rng.standard_normal(m), 400, 4000) * np.exp(-tt * 70)
    thump = np.sin(2 * np.pi * 70 * tt) * np.exp(-tt * 35)
    pop[i:] += gain * (crack + 0.8 * thump)
save('pop.wav', np.tanh(pop * 1.5) / np.tanh(1.5) * 0.85)
print('ok')
