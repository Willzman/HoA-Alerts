"""Generate HoA Alerts' own alert sounds.

These are synthesized from scratch (no recordings or samples), so they are
original to this project and safe to ship with it. Run from the repository
root:

    python3 tools/make_sounds.py

Writes 16-bit mono 44.1 kHz WAV files to HoAAlerts/Sounds/. The game
client plays WAV (PCM/ADPCM) and MP3 through PlaySoundFile.
"""

import os
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "HoAAlerts", "Sounds")


def t(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def envelope(n, attack=0.005, decay=6.0):
    x = np.arange(n) / RATE
    env = np.exp(-decay * x)
    a = int(RATE * attack)
    if a:
        env[:a] *= np.linspace(0, 1, a)
    return env


def tone(freq, seconds, partials=((1, 1.0),), decay=6.0, attack=0.005):
    x = t(seconds)
    sig = sum(amp * np.sin(2 * np.pi * freq * mult * x) for mult, amp in partials)
    return sig * envelope(len(x), attack, decay)


def place(track, sound, at):
    start = int(RATE * at)
    end = min(len(track), start + len(sound))
    track[start:end] += sound[: end - start]


def finish(sig, peak=0.9, loudness_db=-14.0):
    """Fade the tail, then match loudness (RMS over the audible part) without clipping."""
    fade = int(RATE * 0.01)
    sig[-fade:] *= np.linspace(1, 0, fade)
    sig = sig / np.max(np.abs(sig))
    audible = sig[np.abs(sig) > 0.02]
    rms = np.sqrt(np.mean(audible ** 2))
    gain = min(10 ** (loudness_db / 20) / rms, peak)
    return sig * gain


def chime():
    """Two bright rising notes, like a pickup sparkle."""
    track = np.zeros(int(RATE * 0.9))
    soft = ((1, 1.0), (2, 0.35), (3, 0.12))
    place(track, tone(1318.5, 0.6, soft, decay=7), 0.0)    # E6
    place(track, tone(1760.0, 0.75, soft, decay=6), 0.12)  # A6
    return finish(track)


def bell():
    """A single struck bell with inharmonic partials and a long ring."""
    partials = ((0.5, 0.5), (1, 1.0), (1.19, 0.6), (1.56, 0.45), (2.0, 0.35), (2.74, 0.2), (3.76, 0.1))
    return finish(tone(660.0, 1.6, partials, decay=3.2, attack=0.002))


def alarm():
    """Three quick, urgent beeps."""
    track = np.zeros(int(RATE * 0.62))
    beep_partials = ((1, 1.0), (3, 0.25), (5, 0.08))   # a softened square
    for i in range(3):
        beep = tone(987.8, 0.13, beep_partials, decay=4, attack=0.004)
        place(track, beep, i * 0.18)
    return finish(track)


def horn():
    """A short, low brass-like call with a little vibrato."""
    x = t(0.85)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * x)
    phase = 2 * np.pi * np.cumsum(220.0 * vib) / RATE
    sig = sum(np.sin(k * phase) / k ** 1.2 for k in range(1, 9))
    env = np.minimum(1, x / 0.06) * np.where(x > 0.65, np.maximum(0, 1 - (x - 0.65) / 0.2), 1)
    return finish(sig * env)


def write(name, sig):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    data = (np.clip(sig, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(f"{path}: {len(sig) / RATE:.2f} s")


if __name__ == "__main__":
    write("chime.wav", chime())
    write("bell.wav", bell())
    write("alarm.wav", alarm())
    write("horn.wav", horn())
