#!/usr/bin/env python3
"""Importa nel progetto le miniature 3D in formato GLB.

Sono modelli aggiunti a mano (non provengono dal mod TTS, che ha un mesh solo per
i mostri e figurine piatte per i cacciatori), quindi vivono fuori dalla pipeline
di `extract_assets.py`: qui vengono solo copiati in `models/` con un nome stabile.

I file Meshy hanno texture ad altissima risoluzione: se `--shrink` e' attivo e
Pillow riesce a leggerle, le immagini interne vengono ridimensionate, altrimenti
il GLB viene copiato tal quale.
"""
import argparse
import json
import os
import shutil
import struct

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(PROJECT, "models")

SOURCES = {
    "dareon": "01_Adventurers/Dareon/Miniatures",
    "mirah": "01_Adventurers/Mirah/Miniatures",
    "heleren": "01_Adventurers/Heleren/Miniatures",
    "karah": "01_Adventurers/Karah/Miniatures",
    "ljonar": "01_Adventurers/Ljonar/Miniatures",
    "thoreg": "01_Adventurers/Thoreg/Miniatures",
    "vyraxen": "02_Monsters/Vyraxen/Miniatures_and_Models",
    "kharja": "02_Monsters/Kharja/Miniatures_and_Models",
    "dygorax": "02_Monsters/Dygorax/Miniatures_and_Models",
    "toramat": "02_Monsters/Toramat/Miniatures_and_Models",
    "jekoros": "02_Monsters/Jekoros/Miniatures_and_Models",
    "tarragua": "02_Monsters/Tarragua/Miniatures_and_Models",
}
BASE = os.path.join(ROOT, "Organized_Print_Files")

# I GLB pesano decine di MB l'uno: importiamo solo chi e' effettivamente in gioco.
IN_PLAY = {"dareon", "mirah", "thoreg", "vyraxen", "kharja", "dygorax", "toramat",
           "jekoros", "tarragua"}

MAX_TEXTURE = 1024
# I GLB Meshy arrivano a un milione di triangoli l'uno: per una miniatura vista
# dall'alto sono sprecati. `gltfpack` (meshoptimizer) li semplifica al 20% senza
# differenze visibili a distanza di gioco. Se non c'e', si copia il file intero.
#   npm install -g gltfpack     oppure     npx gltfpack
SIMPLIFY = "0.2"


def find_glb(folder):
    path = os.path.join(BASE, folder)
    if not os.path.isdir(path):
        return None
    for name in sorted(os.listdir(path)):
        if name.lower().endswith(".glb"):
            return os.path.join(path, name)
    return None


def shrink_textures(src, dst):
    """Riscrive il GLB ridimensionando le immagini incorporate.

    Un GLB e' un contenitore: header + chunk JSON + chunk binario. Le texture
    sono viste (bufferView) dentro il chunk binario, quindi si possono sostituire
    ricostruendo buffer e offset.
    """
    from io import BytesIO

    from PIL import Image

    with open(src, "rb") as f:
        magic, version, _total = struct.unpack("<III", f.read(12))
        if magic != 0x46546C67:
            raise ValueError("non e' un GLB")
        chunks = []
        while True:
            head = f.read(8)
            if len(head) < 8:
                break
            length, kind = struct.unpack("<II", head)
            chunks.append([kind, f.read(length)])

    gltf = json.loads(chunks[0][1].decode("utf-8"))
    blob = chunks[1][1]
    views = gltf.get("bufferViews", [])
    images = gltf.get("images", [])
    if not images:
        return False

    # Ricostruiamo il binario pezzo per pezzo, sostituendo solo le immagini.
    replacements = {}
    for image in images:
        index = image.get("bufferView")
        if index is None:
            continue
        view = views[index]
        start = view.get("byteOffset", 0)
        data = blob[start:start + view["byteLength"]]
        try:
            img = Image.open(BytesIO(data))
            if max(img.size) <= MAX_TEXTURE:
                continue
            img.thumbnail((MAX_TEXTURE, MAX_TEXTURE), Image.LANCZOS)
            out = BytesIO()
            img.convert("RGB").save(out, format="JPEG", quality=88, optimize=True)
            replacements[index] = out.getvalue()
            image["mimeType"] = "image/jpeg"
        except Exception:
            continue

    if not replacements:
        return False

    new_blob = bytearray()
    for i, view in enumerate(views):
        data = replacements.get(i)
        if data is None:
            start = view.get("byteOffset", 0)
            data = blob[start:start + view["byteLength"]]
        while len(new_blob) % 4:
            new_blob.append(0)
        view["byteOffset"] = len(new_blob)
        view["byteLength"] = len(data)
        new_blob.extend(data)
    while len(new_blob) % 4:
        new_blob.append(0)
    gltf["buffers"] = [{"byteLength": len(new_blob)}]

    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "

    total = 12 + 8 + len(json_bytes) + 8 + len(new_blob)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, version, total))
        f.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(new_blob), 0x004E4942))
        f.write(new_blob)
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--shrink", action="store_true",
                        help="ridimensiona le texture incorporate a %dpx" % MAX_TEXTURE)
    parser.add_argument("--all", action="store_true",
                        help="importa tutti i cacciatori, non solo quelli in gioco")
    args = parser.parse_args()

    wanted = SOURCES if args.all else {k: v for k, v in SOURCES.items() if k in IN_PLAY}
    os.makedirs(OUT, exist_ok=True)
    for slug, folder in wanted.items():
        src = find_glb(folder)
        if src is None:
            print("  ! %s: nessun GLB in %s" % (slug, folder))
            continue
        dst = os.path.join(OUT, slug + ".glb")
        before = os.path.getsize(src)
        done = False
        if args.shrink:
            try:
                done = shrink_textures(src, dst)
            except Exception as exc:
                print("  ! %s: ridimensionamento fallito (%s), copio tal quale" % (slug, exc))
        if not done:
            shutil.copyfile(src, dst)
        after = os.path.getsize(dst)
        print("%-9s %5.1f MB -> %5.1f MB" % (slug, before / 1e6, after / 1e6))


if __name__ == "__main__":
    main()
