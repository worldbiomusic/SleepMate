"""데모 투어 녹화 + 표지/워치 장면 → 소개 탭 영상 (demo-tour.mp4)

장면마다 같은 크기·프레임·인코더로 따로 만든 뒤 concat(-c copy)으로 잇는다.
usage: make_demo_video.py TOUR_MOV REC_START TOUR_LOG OUT_MP4 FRAMES_DIR WATCH_PNG...
"""
import os, re, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

tour, rec_start, log, out, frames_dir, *watch = sys.argv[1:]
rec_start = float(rec_start)
W = 540
ENC = ["-c:v", "libx264", "-crf", "26", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-r", "30"]
work = "video_work"
os.makedirs(work, exist_ok=True)
os.makedirs(frames_dir, exist_ok=True)


def run(cmd):
    print("+", " ".join(cmd[:8]), "…")
    subprocess.run(cmd, check=True)


def encode(cmd_tail, final):
    tmp = final.replace(".mp4", ".part.mp4")
    run(["ffmpeg", "-y", "-loglevel", "error"] + cmd_tail + ENC + ["-an", tmp])
    os.replace(tmp, final)          # 끝까지 성공했을 때만 이름을 바꾼다


# 1) 투어 구간 잘라내기
text = open(log, encoding="utf-8", errors="ignore").read()
start = float(re.search(r"\[Tour\] start ([0-9.]+)", text).group(1))
end = float(re.search(r"\[Tour\] end ([0-9.]+)", text).group(1))
off, dur = max(0, start - rec_start - 0.3), end - start + 0.6
print(f"tour offset {off:.2f}s, duration {dur:.2f}s")
encode(["-ss", f"{off:.2f}", "-i", tour, "-t", f"{dur:.2f}",
        "-vf", f"scale={W}:-2,fps=30,format=yuv420p"], f"{work}/2-tour.mp4")
H = int(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                 "stream=height", "-of", "csv=p=0", f"{work}/2-tour.mp4"]).strip())
print("size", W, H)

# 2) 글꼴
cands = ["/System/Library/Fonts/AppleSDGothicNeo.ttc", "/System/Library/Fonts/Supplemental/AppleGothic.ttf"]
FONT = next(p for p in cands if os.path.exists(p))


def font(size):
    return ImageFont.truetype(FONT, size)


def center(d, y, s, f, fill):
    w = d.textlength(s, font=f)
    d.text(((W - w) / 2, y), s, font=f, fill=fill)


def still(img, seconds, name):
    png = f"{work}/{name}.png"
    img.save(png)
    fade = f"fade=t=in:st=0:d=0.4,fade=t=out:st={seconds - 0.4:.2f}:d=0.4"
    encode(["-framerate", "30", "-i", png,
            "-vf", f"format=yuv420p,loop=-1:1,trim=duration={seconds},{fade}"], f"{work}/{name}.mp4")


def night_bg():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):                                   # 밤하늘 세로 그라데이션
        t = y / H
        d.line([(0, y), (W, y)], fill=(int(26 + 40 * t), int(24 + 18 * t), int(70 + 60 * t)))
    import random
    r = random.Random(7)
    for _ in range(70):
        x, y, s = r.random() * W, r.random() * H * 0.6, 1 + r.random() * 2
        d.ellipse([x, y, x + s, y + s], fill=(255, 255, 255))
    return img, d


# 3) 표지
img, d = night_bg()
cx, cy = W // 2, int(H * 0.32)
d.ellipse([cx - 70, cy - 70, cx + 70, cy + 70], fill=(255, 238, 180))
d.ellipse([cx - 40, cy - 92, cx + 100, cy + 48], fill=(34, 30, 84))
center(d, int(H * 0.47), "이젠 잘 때도 됐잖아", font(46), (255, 255, 255))
center(d, int(H * 0.47) + 66, "SleepMate AI · 사용 예시", font(26), (210, 205, 255))
center(d, int(H * 0.47) + 110, "평택대학교 AI융합대학원 · AI응용융합연구", font(19), (170, 165, 220))
still(img, 2.8, "1-title")

# 4) 애플워치 장면
img, d = night_bg()
center(d, int(H * 0.12), "애플워치에서도", font(40), (255, 255, 255))
center(d, int(H * 0.12) + 58, "남은 시간 · 앱 사용 · ‘오늘은 여기까지’", font(22), (210, 205, 255))
shots = [Image.open(p).convert("RGB") for p in watch[:3]]
if shots:
    tw = (W - 40 - 20 * (len(shots) - 1)) // len(shots)
    x = 20
    for s in shots:
        th = int(s.height * tw / s.width)
        s = s.resize((tw, th))
        mask = Image.new("L", s.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, tw, th], radius=int(tw * 0.22), fill=255)
        y = int(H * 0.32)
        d.rounded_rectangle([x - 6, y - 6, x + tw + 6, y + th + 6], radius=int(tw * 0.26), fill=(20, 20, 24))
        img.paste(s, (x, y), mask)
        x += tw + 20
    labels = ["오늘 밤", "어젯밤", "호흡"]
    for i, lab in enumerate(labels[:len(shots)]):
        lx = 20 + i * (tw + 20) + tw / 2
        w = d.textlength(lab, font=font(20))
        d.text((lx - w / 2, int(H * 0.32) + th + 18), lab, font=font(20), fill=(220, 220, 240))
center(d, int(H * 0.78), "판단은 아이폰, 손목은 알려 주고 입력받기", font(22), (255, 255, 255))
center(d, int(H * 0.78) + 40, "알림은 아이폰이 잠겨 있으면 워치에서 진동해요", font(18), (180, 175, 230))
still(img, 5.0, "3-watch")

# 5) 잇기
with open(f"{work}/list.txt", "w") as f:
    for n in ["1-title", "2-tour", "3-watch"]:
        f.write(f"file '{n}.mp4'\n")
tmp = out.replace(".mp4", ".part.mp4")
run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", f"{work}/list.txt",
     "-c", "copy", "-movflags", "+faststart", tmp])
os.replace(tmp, out)

# 6) 확인용 프레임 (가장 많이 보이는 순간들)
total = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                       "-of", "csv=p=0", out]).strip())
for i, t in enumerate([1.4, 5, 9.5, 14, 18.5, 23, 28, total - 2.5]):
    if t < total:
        run(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{t:.2f}", "-i", out, "-frames:v", "1",
             "-q:v", "3", f"{frames_dir}/f{i}-{t:.0f}s.jpg"])
print(f"done: {out} {os.path.getsize(out) / 1e6:.1f} MB, {total:.1f}s")
