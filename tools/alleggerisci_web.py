#!/usr/bin/env python3
"""Alleggerisce il progetto PRIMA dell'esportazione web (lo usa solo l'azione di GitHub Pages).

Nel progetto restano gli originali a piena qualità per la versione desktop; sulla copia che
l'azione esporta per il browser:
  1. le miniature 3D (models/**/*.glb) vengono semplificate con gltfpack a non più di
     MAX_TRIANGOLI triangoli ciascuna (gli sculti originali arrivano a 2 milioni);
  2. le immagini 2D importate senza perdita (carte, plance, segnalini) passano a WebP con
     perdita e al massimo LATO_MAX pixel di lato;
  3. ai modelli non si generano LOD e ombre separate, che per una plancia vista da vicino
     raddoppiano i dati senza servire.

Uso: python3 tools/alleggerisci_web.py   (richiede npx gltfpack nel PATH)
"""
import json, os, re, struct, subprocess, sys

MAX_TRIANGOLI = 60000
LATO_MAX = 2048
QUALITA = 0.82
RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def triangoli(glb):
    with open(glb, "rb") as f:
        dati = f.read()
    lung = struct.unpack_from("<I", dati, 12)[0]
    j = json.loads(dati[20:20 + lung])
    tot = 0
    for m in j.get("meshes", []):
        for p in m.get("primitives", []):
            if "indices" in p:
                tot += j["accessors"][p["indices"]]["count"] // 3
            else:
                tot += j["accessors"][p["attributes"]["POSITION"]]["count"] // 3
    return tot


def semplifica_modelli():
    for cartella, _, file in os.walk(os.path.join(RADICE, "models")):
        for nome in file:
            if not nome.endswith(".glb"):
                continue
            p = os.path.join(cartella, nome)
            t = triangoli(p)
            if t <= MAX_TRIANGOLI:
                continue
            ratio = MAX_TRIANGOLI / t
            tmp = p + ".tmp.glb"
            subprocess.run(["npx", "--yes", "gltfpack", "-i", p, "-o", tmp, "-si", "%.4f" % ratio, "-noq", "-kn", "-km"], check=True,
                           stdout=subprocess.DEVNULL)
            prima = os.path.getsize(p)
            os.replace(tmp, p)
            print(f"{os.path.relpath(p, RADICE)}: {t} -> ~{MAX_TRIANGOLI} triangoli, {prima >> 20} -> {os.path.getsize(p) >> 20} MB")


def imposta(testo, chiave, valore):
    if re.search(rf"^{re.escape(chiave)}=", testo, re.M):
        return re.sub(rf"^{re.escape(chiave)}=.*$", f"{chiave}={valore}", testo, flags=re.M)
    return testo.rstrip("\n") + f"\n{chiave}={valore}\n"


def alleggerisci_import():
    immagini = modelli = 0
    for cartella, dirs, file in os.walk(RADICE):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for nome in file:
            if not nome.endswith(".import"):
                continue
            p = os.path.join(cartella, nome)
            t = open(p, encoding="utf-8").read()
            prima = t
            if 'importer="texture"' in t:
                if re.search(r"^compress/mode=0$", t, re.M):
                    t = imposta(t, "compress/mode", "1")
                    t = imposta(t, "compress/lossy_quality", str(QUALITA))
                t = imposta(t, "process/size_limit", str(LATO_MAX))
                immagini += t != prima
            elif 'importer="scene"' in t:
                t = imposta(t, "meshes/generate_lods", "false")
                t = imposta(t, "meshes/create_shadow_meshes", "false")
                modelli += t != prima
            if t != prima:
                open(p, "w", encoding="utf-8").write(t)
    print(f"impostazioni web: {immagini} immagini, {modelli} modelli")


if __name__ == "__main__":
    semplifica_modelli()
    alleggerisci_import()
