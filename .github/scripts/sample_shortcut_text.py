#!/usr/bin/env python3
"""단축어가 만들어 줄 텍스트를 흉내 낸 샘플 (CI에서 sleepmate://import 경로 검증용).
지난밤(어제 23:20 시작) 한 밤을 한국어/영어 값, ISO/한국어 날짜 형식을 섞어서 만든다."""
import datetime as dt
import sys
import urllib.parse

tz = dt.datetime.now().astimezone().tzinfo
today = dt.datetime.now(tz).replace(hour=0, minute=0, second=0, microsecond=0)
t = today - dt.timedelta(minutes=40)            # 어제 23:20

pattern = [("코어", 30), ("깊은 수면", 40), ("코어", 35), ("REM", 20), ("Core", 40),
           ("깊은 수면", 20), ("깨어 있음", 5), ("코어", 45), ("REM", 30), ("코어", 40),
           ("REM 수면", 25), ("깨어 있음", 3), ("코어", 30)]

def ko(d):  # 한국어 기본 날짜 형식: 2026. 11. 13. 오전 1:05
    ampm = "오전" if d.hour < 12 else "오후"
    h = d.hour % 12 or 12
    return f"{d.year}. {d.month}. {d.day}. {ampm} {h}:{d.minute:02d}"

lines = []
for i, (v, m) in enumerate(pattern):
    e = t + dt.timedelta(minutes=m)
    if i == 4:
        lines.append(f"{ko(t)}|{ko(e)}|{v}|Apple Watch")
    else:
        lines.append(f"{t.isoformat(timespec='seconds')}|{e.isoformat(timespec='seconds')}|{v}|Apple Watch")
    t = e
lines.append("이 줄은 형식이 틀려서 건너뛰어야 함")
text = "\n".join(lines)

if len(sys.argv) > 1 and sys.argv[1] == "--raw":
    print(text)
else:
    print("sleepmate://import?data=" + urllib.parse.quote(text, safe=""))
