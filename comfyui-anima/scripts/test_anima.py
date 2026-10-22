r"""Anima img2img denoise test: run the saved API workflow on one image via a running
ComfyUI server, save the result to a separate folder and compare it with the original.

Usage (ComfyUI embedded python):
  python_embeded\python.exe test_anima.py --input D:\AnimaTest\input\my.png ^
      --comfy-root D:\ComfyUI_windows_portable\ComfyUI --out D:\AnimaTest\results

The original file is only read, never modified. The script does not judge quality:
it writes measurements plus zoomed crops so a person can check eyes, hair/fur and fabric.
"""
import argparse
import json
import shutil
import sys
import time
import urllib.parse
import urllib.request
import uuid
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent


def http_json(url, data=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def run_workflow(server, workflow, timeout):
    client_id = str(uuid.uuid4())
    res = http_json(f"http://{server}/prompt", {"prompt": workflow, "client_id": client_id})
    if res.get("node_errors"):
        raise RuntimeError("workflow validation failed: " + json.dumps(res["node_errors"], ensure_ascii=False))
    pid = res["prompt_id"]
    start = time.time()
    while time.time() - start < timeout:
        hist = http_json(f"http://{server}/history/{pid}")
        if pid in hist:
            entry = hist[pid]
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                raise RuntimeError("execution error: " + json.dumps(status.get("messages"), ensure_ascii=False)[:2000])
            for out in entry.get("outputs", {}).values():
                for img in out.get("images", []):
                    return img, time.time() - start
            raise RuntimeError("finished without an output image")
        time.sleep(1)
    raise TimeoutError(f"no result after {timeout}s")


def fetch_image(server, img):
    q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img["subfolder"], "type": img["type"]})
    with urllib.request.urlopen(f"http://{server}/view?{q}", timeout=60) as r:
        return r.read()


def center_crop_like_vae(arr, ratio=8):
    # Mirrors comfy.sd.VAE.vae_encode_crop_pixels: floor each side to a multiple of 8, centered.
    h, w = arr.shape[:2]
    nh, nw = (h // ratio) * ratio, (w // ratio) * ratio
    oy, ox = (h % ratio) // 2, (w % ratio) // 2
    return arr[oy:oy + nh, ox:ox + nw], (ox, oy)


def psnr(a, b):
    mse = np.mean((a.astype(np.float64) - b.astype(np.float64)) ** 2)
    return float("inf") if mse == 0 else 10 * np.log10(255.0 ** 2 / mse)


def compare(orig_path, result_path, out_dir, stem):
    o_img = Image.open(orig_path)
    r_img = Image.open(result_path)
    o = np.asarray(o_img.convert("RGB"))
    r = np.asarray(r_img.convert("RGB"))
    lines = [f"original : {orig_path}  size={o.shape[1]}x{o.shape[0]}  mode={o_img.mode}",
             f"result   : {result_path}  size={r.shape[1]}x{r.shape[0]}"]
    if o.shape != r.shape:
        oc, (ox, oy) = center_crop_like_vae(o)
        lines.append(f"SIZE CHANGED: VAE center-crop to multiple of 8 (offset x={ox}, y={oy}); "
                     f"lost {o.shape[1] - r.shape[1]}px width, {o.shape[0] - r.shape[0]}px height")
        if oc.shape != r.shape:
            lines.append("WARNING: result size does not match the expected crop either; comparison skipped")
            return lines
        o = oc
    else:
        lines.append("size unchanged (no crop/resize)")
    if o_img.mode in ("RGBA", "LA", "P"):
        lines.append("NOTE: original has alpha/palette; result is RGB (transparency is not kept)")

    d = np.abs(o.astype(np.int16) - r.astype(np.int16)).max(axis=2)
    lines += [f"PSNR {psnr(o, r):.2f} dB | mean abs diff {d.mean():.2f} | 99th pct {np.percentile(d, 99):.0f} | max {d.max()}",
              f"pixels changed >8: {np.mean(d > 8) * 100:.2f}%  >24: {np.mean(d > 24) * 100:.2f}%"]

    heat = np.clip(d.astype(np.float32) * 8, 0, 255).astype(np.uint8)
    Image.fromarray(heat).save(out_dir / f"{stem}_diff_x8.png")
    side = np.concatenate([o, r], axis=1)
    Image.fromarray(side).save(out_dir / f"{stem}_side_by_side.png")

    # Zoomed crops of the 4 most-changed regions (and the image centre) for eye / fur / fabric review.
    h, w = d.shape
    g = 8
    bh, bw = max(1, h // g), max(1, w // g)
    scores = [(d[y * bh:(y + 1) * bh, x * bw:(x + 1) * bw].mean(), y, x) for y in range(g) for x in range(g)]
    picks = [s[1:] for s in sorted(scores, reverse=True)[:4]] + [(g // 2, g // 2)]
    tiles = []
    for y, x in picks:
        sl = (slice(y * bh, (y + 1) * bh), slice(x * bw, (x + 1) * bw))
        tile = np.concatenate([o[sl], r[sl], np.stack([heat[sl]] * 3, axis=2)], axis=1)
        tiles.append(np.asarray(Image.fromarray(tile).resize((tile.shape[1] * 3, tile.shape[0] * 3), Image.NEAREST)))
    width = max(t.shape[1] for t in tiles)
    tiles = [np.pad(t, ((0, 6), (0, width - t.shape[1]), (0, 0))) for t in tiles]
    Image.fromarray(np.concatenate(tiles, axis=0)).save(out_dir / f"{stem}_zoom_orig_result_diff.png")
    lines.append("zoom sheet rows = 4 most-changed regions + centre; columns = original | result | diff x8 (3x nearest)")
    lines.append("QUALITY NOT AUTO-JUDGED: inspect eyes, hair/fur, fabric and line art in the zoom sheet yourself.")
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--comfy-root", required=True, help="folder that contains main.py")
    ap.add_argument("--out", default=r"D:\AnimaTest\results")
    ap.add_argument("--server", default="127.0.0.1:8188")
    ap.add_argument("--workflow", default=str(HERE.parent / "workflows" / "Anima_img2img_denoise0.1_api.json"))
    ap.add_argument("--timeout", type=int, default=900)
    a = ap.parse_args()

    src = Path(a.input).resolve()
    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    if out_dir.resolve() == src.parent:
        sys.exit("results folder must differ from the original's folder")

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = f"{src.stem}_{stamp}"
    # Copy (never move) the original into ComfyUI's input folder under a unique name.
    staged = Path(a.comfy_root) / "input" / f"anima_test_{stamp}{src.suffix.lower()}"
    shutil.copy2(src, staged)

    wf = json.loads(Path(a.workflow).read_text(encoding="utf-8"))
    wf["4"]["inputs"]["image"] = staged.name
    wf["10"]["inputs"]["filename_prefix"] = f"anima_denoise/{stem}"
    s = wf["8"]["inputs"]
    settings = f"denoise={s['denoise']} steps={s['steps']} cfg={s['cfg']} sampler={s['sampler_name']} scheduler={s['scheduler']} seed={s['seed']}"
    print("running:", settings)

    img, secs = run_workflow(a.server, wf, a.timeout)
    result = out_dir / f"{stem}_anima_d0.1.png"
    result.write_bytes(fetch_image(a.server, img))

    lines = [f"date {stamp} | {settings} | {secs:.1f}s"] + compare(src, result, out_dir, stem)
    (out_dir / f"{stem}_report.txt").write_text("\n".join(lines), encoding="utf-8")
    print("\n".join(lines))
    print(f"\nsaved to {out_dir}")


if __name__ == "__main__":
    main()
