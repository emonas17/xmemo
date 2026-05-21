from pathlib import Path
import math
import struct
import wave
import zlib

ROOT = Path(__file__).resolve().parents[1]


def chunk(kind: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )


def distance(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    c = max(0, min(1, (wx * vx + wy * vy) / (vx * vx + vy * vy)))
    qx, qy = ax + c * vx, ay + c * vy
    return ((px - qx) ** 2 + (py - qy) ** 2) ** 0.5


def write_icon(path: Path, size: int, bg):
    thickness = max(2, int(size * 0.15))
    a = (int(size * 0.25), int(size * 0.17), int(size * 0.75), int(size * 0.83))
    b = (int(size * 0.75), int(size * 0.17), int(size * 0.25), int(size * 0.83))

    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            d = min(distance(x, y, *a), distance(x, y, *b))
            row.append(1 if d <= thickness / 2 else 0)
        rows.append(b"\x00" + bytes(row))

    palette = bytes(bg + (255, 255, 255))
    data = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 3, 0, 0, 0))
        + chunk(b"PLTE", palette)
        + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def write_wav(path: Path, freqs):
    sample_rate = 8000
    duration = 0.16
    total = int(sample_rate * duration)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(1)
        wav.setframerate(sample_rate)
        frames = bytearray()
        for i in range(total):
            t = i / sample_rate
            envelope = min(1, i / (sample_rate * 0.01), (total - i) / (sample_rate * 0.025))
            freq = freqs[min(len(freqs) - 1, int(t / (duration / len(freqs))))]
            frames.append(max(0, min(255, int(128 + 115 * envelope * math.sin(2 * math.pi * freq * t)))))
        wav.writeframes(bytes(frames))


def main():
    icons = [
        ("AppIcon", (238, 31, 31), "red"),
        ("AppIconRAL8025", (96, 61, 49), "ral8025"),
        ("AppIconSilver", (174, 178, 184), "silver"),
    ]
    sizes = [
        (40, "20@2x"),
        (60, "20@3x"),
        (58, "29@2x"),
        (87, "29@3x"),
        (80, "40@2x"),
        (120, "40@3x"),
        (120, "60@2x"),
        (180, "60@3x"),
        (1024, ""),
    ]
    assets = ROOT / "VoiceReminder/VoiceReminder/Assets.xcassets"
    variants = ROOT / "VoiceReminder/IconVariants"

    for name, bg, variant_name in icons:
        folder = assets / f"{name}.appiconset"
        for size, label in sizes:
            filename = f"{name}.png" if size == 1024 else f"{name}-{label}.png"
            write_icon(folder / filename, size, bg)
        write_icon(variants / f"Xmemo-icon-{variant_name}.png", 1024, bg)

    sound_folder = ROOT / "VoiceReminder/VoiceReminder"
    write_wav(sound_folder / "xmemo_bell.wav", [880, 1175])
    write_wav(sound_folder / "xmemo_chime.wav", [660, 990, 1320])
    write_wav(sound_folder / "xmemo_signal.wav", [1200, 900, 1200])


if __name__ == "__main__":
    main()
