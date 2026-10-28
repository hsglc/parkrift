"""Builds the game's sounds from free recorded sound packs (replacing the old synthesized ones).

Sources (downloaded into one folder, see README credits):
  oga/loop_*.wav          "racing car engine sound loops" (banditracer.eu), OpenGameArt, CC0
  oga/pack/*.ogg          "Car Sound Effects Pack", OpenGameArt, CC0 (horn)
  sr/sounds/...           "Stunt Rally sounds", OpenGameArt, CC-BY-SA 3.0 (VDrift tyre squeal,
                          wind, bump; crash hits by Halleck; boost by nathanshadow; HUD jingles)
  kenney/x_*/...          Kenney "Impact Sounds" and "Interface Sounds", CC0
  siren/siren_0.mp3       "Sirens and Alarm Noise", OpenGameArt, CC0
  music/chilllofir-loop.ogg  "Chill lofi inspired [loop edit]" by omfgdude, OpenGameArt, CC0

Every sound becomes 22050 Hz mono 16-bit WAV (the effect players share one format); loops get
a crossfade at the seam; levels are matched so nothing jumps out.

Usage: python3 make_real_sounds.py <source folder> <Hop/Audio>
"""
import sys, os, glob, subprocess
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfiltfilt

SR = 22050
SRC, OUT = sys.argv[1], sys.argv[2]


def load(path):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-ac', '1', '-ar', str(SR), '-f', 's16le', '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.int16).astype(np.float64) / 32768


def find(pattern):
    hits = sorted(glob.glob(os.path.join(SRC, pattern), recursive=True))
    if not hits:
        raise SystemExit('missing ' + pattern)
    return hits[0]


def rms(x):
    return np.sqrt(np.mean(x ** 2)) + 1e-9


def level(x, target_rms, peak=0.95):
    y = x * (target_rms / rms(x))
    top = np.abs(y).max()
    return y * (peak / top) if top > peak else y


def fade(x, a=0.005, b=0.03):
    y = x.copy()
    na, nb = int(a * SR), int(b * SR)
    if na:
        y[:na] *= np.linspace(0, 1, na)
    if nb:
        y[-nb:] *= np.linspace(1, 0, nb)
    return y


def loop(x, cross=0.12):
    """Seamless loop: the tail is crossfaded into the head."""
    n = int(cross * SR)
    body = x[:-n].copy()
    ramp = np.linspace(0, 1, n)
    body[:n] = body[:n] * ramp + x[-n:] * (1 - ramp)
    return body


def band(x, low, high):
    sos = butter(2, [low / (SR / 2), high / (SR / 2)], btype='band', output='sos')
    return sosfiltfilt(sos, x)


def trim(x, start, end=None):
    return x[int(start * SR):int(end * SR) if end else None]


def save(name, x):
    wavfile.write(os.path.join(OUT, name), SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    print(f'{name:16s} {len(x) / SR:5.2f}s rms {rms(x):.3f}')


# Engine: two recorded loops (idle-ish and higher revs), already seamless
save('engine_low.wav', level(load(find('oga/loop_0.wav')), 0.30))
save('engine_high.wav', level(load(find('oga/loop_4_0.wav')), 0.30))

# Tyres: VDrift's squeal as a loop
squeal = load(find('sr/sounds/tire_squeal.wav'))
save('skid.wav', level(loop(trim(squeal, 0.3, 2.3), 0.25), 0.22))

# Crash: a heavy metal hit, a short scrape tail and a little glass
hit = load(find('sr/sounds/crash/09.wav'))
scrape = trim(load(find('sr/sounds/crash/scrap.wav')), 0, 0.9)
glass = load(find('kenney/**/impactGlass_light_001.ogg'))
crash = np.zeros(int(1.0 * SR))
crash[:len(hit)] += level(hit, 0.30)
crash[int(0.05 * SR):int(0.05 * SR) + len(scrape)] += fade(level(scrape, 0.08), 0.01, 0.5)[:len(crash) - int(0.05 * SR)]
crash[int(0.02 * SR):int(0.02 * SR) + len(glass)] += level(glass, 0.05)
save('crash.wav', fade(level(crash, 0.22), 0.002, 0.25))

save('bump.wav', fade(level(load(find('sr/sounds/bump_front.wav')), 0.22), 0.001, 0.05))
save('nitro.wav', fade(level(load(find('sr/sounds/boost.wav')), 0.20), 0.01, 0.4))

# Near miss: a short rush of real wind
wind = load(find('sr/sounds/wind.wav'))
rush = band(trim(wind, 0.4, 1.1), 300, 5000)
env = np.sin(np.linspace(0, np.pi, len(rush))) ** 1.5
save('whoosh.wav', level(rush * env, 0.16))
save('wind.wav', level(loop(wind, 0.4), 0.15))

# Countdown, start, finish
save('beep.wav', fade(level(load(find('sr/sounds/hud/check.wav')), 0.18), 0.001, 0.02))
save('go.wav', fade(level(load(find('sr/sounds/hud/lap.wav')), 0.18), 0.002, 0.2))
save('park.wav', fade(level(trim(load(find('sr/sounds/hud/win0.ogg')), 0, 1.8), 0.16), 0.002, 0.5))

# Interface: a soft short click
save('click.wav', fade(level(load(find('kenney/**/click_005.ogg')), 0.10), 0.0005, 0.005))
# Gear change: a light, dull mechanical tick
save('shift.wav', fade(level(band(load(find('kenney/**/impactPlate_light_002.ogg')), 120, 2500), 0.06), 0.001, 0.15))

save('horn.wav', fade(level(load(find('oga/pack/Car_Horn.ogg')), 0.18), 0.002, 0.05))

# Police siren: three yelp cycles from the recording, looped
siren = trim(load(find('siren/siren_0.mp3')), 36.5, 38.75)
save('siren.wav', level(loop(siren, 0.15), 0.20))

# Menu and race music: a calm lofi loop (AAC)
music = os.path.join(OUT, 'music.m4a')
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', find('music/chilllofir-loop.ogg'), '-ac', '2', '-ar', '44100',
                '-af', 'loudnorm=I=-20:TP=-2', '-c:a', 'aac', '-b:a', '112k', music], check=True)
print('music.m4a', os.path.getsize(music) // 1024, 'KB')
