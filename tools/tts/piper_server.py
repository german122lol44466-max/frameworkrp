"""Свой сервер голосов для NPC: нейросетевые русские голоса Piper (Денис, Дмитрий, Ирина, Руслан).

Установка (на машине с игровым сервером или любой другой, доступной игрокам):
    pip install piper-tts
    python3 piper_server.py --port 5002
Голоса скачиваются сами при первом запуске (huggingface.co/rhasspy/piper-voices, ~60 МБ каждый).
В консоли игрового сервера:  nyrp_tts_server "http://<внешний-IP>:5002"
Порт 5002 должен быть открыт снаружи (игроки качают звук сами).

Запрос: GET /tts?voice=ru_RU-denis-medium&text=Привет  ->  audio/wav (готовые фразы кэшируются на диске).
"""
import argparse
import hashlib
import io
import os
import urllib.parse
import urllib.request
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VOICES = {
    "ru_RU-denis-medium": "ru/ru_RU/denis/medium",
    "ru_RU-dmitri-medium": "ru/ru_RU/dmitri/medium",
    "ru_RU-irina-medium": "ru/ru_RU/irina/medium",
    "ru_RU-ruslan-medium": "ru/ru_RU/ruslan/medium",
}
BASE = "https://huggingface.co/rhasspy/piper-voices/resolve/main/"
HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, "voices")
CACHE = os.path.join(HERE, "cache")
_loaded = {}


def voice(name):
    if name not in VOICES:
        name = "ru_RU-dmitri-medium"
    if name in _loaded:
        return _loaded[name]
    from piper import PiperVoice
    os.makedirs(MODELS, exist_ok=True)
    onnx = os.path.join(MODELS, name + ".onnx")
    for ext in (".onnx", ".onnx.json"):
        path = os.path.join(MODELS, name + ext)
        if not os.path.exists(path):
            print("скачиваю", name + ext)
            urllib.request.urlretrieve(BASE + VOICES[name] + "/" + name + ext, path)
    _loaded[name] = PiperVoice.load(onnx)
    return _loaded[name]


def synth(name, text):
    os.makedirs(CACHE, exist_ok=True)
    key = hashlib.sha1((name + "|" + text).encode()).hexdigest()
    path = os.path.join(CACHE, key + ".wav")
    if not os.path.exists(path):
        v = voice(name)
        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            # piper-tts >= 1.3: synthesize_wav; старые версии: synthesize
            if hasattr(v, "synthesize_wav"):
                v.synthesize_wav(text, w)
            else:
                v.synthesize(text, w)
        with open(path, "wb") as f:
            f.write(buf.getvalue())
    with open(path, "rb") as f:
        return f.read()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        if u.path != "/tts":
            self.send_error(404)
            return
        q = urllib.parse.parse_qs(u.query)
        text = (q.get("text") or [""])[0][:800].strip()
        if not text:
            self.send_error(400)
            return
        try:
            data = synth((q.get("voice") or [""])[0], text)
        except Exception as e:  # noqa: BLE001
            self.send_error(500, str(e))
            return
        self.send_response(200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "public, max-age=86400")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=5002)
    ap.add_argument("--host", default="0.0.0.0")
    a = ap.parse_args()
    print(f"TTS Piper: http://{a.host}:{a.port}/tts?voice=ru_RU-denis-medium&text=Привет")
    ThreadingHTTPServer((a.host, a.port), Handler).serve_forever()
